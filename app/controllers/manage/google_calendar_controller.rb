# frozen_string_literal: true

module Manage
  # Organization settings → Integrations → Google Calendar (Tim, 2026-11-11):
  # connect with Google's own sign-in, and CocoScout makes one calendar in
  # that account and keeps it: shows and events, rentals under contract, each
  # in its room's color. One direction only; nothing in Google is read.
  class GoogleCalendarController < Manage::ManageController
    before_action :set_organization, except: :callback
    before_action :ensure_user_can_manage, except: :callback
    before_action :set_integration, only: %i[show update sync disconnect]

    def show
      @rooms = @organization.calendar_rooms
      @event_count = @integration ? @integration.calendar_sync_events.count : 0
      # A real coming date, titled as it will be on the calendar.
      if @integration&.connected?
        coming = Show.where(production: @organization.productions.schedulable.active, canceled: false)
                     .where(date_and_time: Time.current..).order(:date_and_time).first
        @preview = GoogleCalendarEntry.new(@integration, coming) if coming
      end
    end

    def connect
      if (problem = GoogleCalendarApi.setup_problem)
        return redirect_to manage_organization_google_calendar_path(@organization), alert: problem
      end

      state = SecureRandom.hex(16)
      session[:google_calendar_oauth] = { "state" => state, "organization_id" => @organization.id }
      redirect_to GoogleCalendarApi.authorize_url(state: state, redirect_uri: manage_google_calendar_callback_url), allow_other_host: true
    end

    def callback
      pending = session.delete(:google_calendar_oauth) || {}
      organization = Current.user.accessible_organizations.find_by(id: pending["organization_id"])
      if organization.nil? || !organization.manageable_by?(Current.user) || params[:state].blank? || params[:state] != pending["state"]
        return redirect_to manage_organizations_path, alert: "That Google sign-in did not match. Try connecting again."
      end
      if params[:error].present?
        return redirect_to manage_organization_google_calendar_path(organization), alert: "Google Calendar did not connect: #{params[:error].to_s.tr('_', ' ')}"
      end

      tokens = GoogleCalendarApi.exchange_code(params[:code], redirect_uri: manage_google_calendar_callback_url)
      if tokens["refresh_token"].blank?
        return redirect_to manage_organization_google_calendar_path(organization), alert: "Google did not hand back a lasting connection. Try connecting again."
      end

      integration = organization.integrations.find_or_initialize_by(provider: "google_calendar")
      # A new calendar each time someone connects: the last one, if any, was
      # in whatever account they used then.
      integration.settings = integration.settings.except("calendar_id", "calendar_name").merge("account_email" => tokens["email"])
      integration.connect!(tokens: tokens.slice("access_token", "refresh_token", "expires_at"), by: Current.user)
      integration.calendar_sync_events.delete_all
      GoogleCalendarSync.new(integration).create_calendar!
      GoogleCalendarFullSyncJob.perform_later(organization.id)
      redirect_to manage_organization_google_calendar_path(organization),
                  notice: "Connected. CocoScout made the calendar \"#{integration.calendar_name}\" in your Google account, and your dates are on their way to it."
    rescue GoogleCalendarApi::Error => e
      redirect_to manage_organization_google_calendar_path(organization), alert: "Google Calendar did not connect: #{e.message}"
    end

    def update
      return redirect_to manage_organization_google_calendar_path(@organization), alert: "Connect Google Calendar first." unless @integration&.connected?

      settings = @integration.settings.dup
      settings["event_types"] = EventTypes.all.index_with { |type| params.dig(:event_types, type) == "1" }
      settings.delete("include")
      settings["title"] = Integration::CALENDAR_TITLE_PARTS.keys.index_with { |key| params.dig(:title, key) == "1" }
      room_ids = @organization.calendar_rooms.map { |room| room.id.to_s }
      colors = params.fetch(:room_colors, {}).permit!.to_h
      settings["room_colors"] = colors.slice(*room_ids).select { |_, color| Integration::CALENDAR_COLORS.key?(color.to_s) }
      settings["other_color"] = params[:other_color].to_s if Integration::CALENDAR_COLORS.key?(params[:other_color].to_s)
      @integration.update!(settings: settings)
      GoogleCalendarFullSyncJob.perform_later(@organization.id)
      redirect_to manage_organization_google_calendar_path(@organization), notice: "Saved. The calendar is being brought up to date."
    end

    def sync
      return redirect_to manage_organization_google_calendar_path(@organization), alert: "Connect Google Calendar first." unless @integration&.connected?

      GoogleCalendarFullSyncJob.perform_later(@organization.id, force: true)
      redirect_to manage_organization_google_calendar_path(@organization), notice: "Writing every date to the calendar again. Give it a minute."
    end

    def disconnect
      if @integration
        begin
          GoogleCalendarApi.revoke(@integration.refresh_token) if @integration.refresh_token.present?
        rescue GoogleCalendarApi::Error => e
          Rails.logger.warn("[Google Calendar] revoke failed: #{e.message}")
        end
        @integration.calendar_sync_events.delete_all
        @integration.disconnect!
      end
      redirect_to section_manage_organization_path(@organization, section: "integrations"),
                  notice: "Google Calendar is disconnected. The calendar stays in your Google account as it is; CocoScout no longer changes it."
    end

    private

    def set_organization
      @organization = Current.user.accessible_organizations.find(params[:id])
    end

    def ensure_user_can_manage
      return if @organization.manageable_by?(Current.user)

      redirect_to manage_organizations_path, alert: "You don't have permission to manage this organization"
    end

    def set_integration
      @integration = @organization.integrations.google_calendar.first
    end
  end
end
