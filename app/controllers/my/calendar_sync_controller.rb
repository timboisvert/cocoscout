# frozen_string_literal: true

module My
  class CalendarSyncController < ApplicationController
    before_action :set_person
    before_action :set_subscription, only: %i[update disconnect]

    def index
      @subscriptions = @person.calendar_subscriptions.order(:provider)
      @groups = @person.groups.active.order(:name)

      # Build list of syncable entities
      @syncable_entities = [ { type: "Person", id: @person.id, name: "Me (#{@person.name})" } ]
      @groups.each do |group|
        @syncable_entities << { type: "Group", id: group.id, name: group.name }
      end
    end

    def connect_google
      state = SecureRandom.urlsafe_base64(32)
      session[:calendar_oauth_state] = state
      session[:calendar_oauth_provider] = "google"

      redirect_to CalendarSync::GoogleService.authorization_url(
        redirect_uri: my_calendar_oauth_callback_url,
        state: state
      ), allow_other_host: true
    end

    def oauth_callback
      # Verify state parameter
      if params[:state] != session[:calendar_oauth_state]
        redirect_to my_calendar_sync_path, alert: "Invalid OAuth state. Please try again."
        return
      end

      provider = session[:calendar_oauth_provider]
      session.delete(:calendar_oauth_state)
      session.delete(:calendar_oauth_provider)

      if params[:error].present?
        redirect_to my_calendar_sync_path, alert: "Authorization was denied: #{params[:error_description]}"
        return
      end

      case provider
      when "google"
        handle_google_callback
      else
        redirect_to my_calendar_sync_path, alert: "Unknown provider."
      end
    end

    def create_ical
      subscription = @person.calendar_subscriptions.find_or_initialize_by(provider: "ical")
      subscription.sync_scope = params[:sync_scope] || "assigned"
      subscription.sync_entities = build_sync_entities
      subscription.enabled = true

      if subscription.save
        redirect_to my_calendar_sync_path, notice: "iCal feed created successfully."
      else
        redirect_to my_calendar_sync_path, alert: subscription.errors.full_messages.join(", ")
      end
    end

    def update
      @subscription.sync_scope = params[:sync_scope] if params[:sync_scope].present?
      @subscription.sync_entities = build_sync_entities if params[:sync_entities].present?
      @subscription.enabled = params[:enabled] == "1" if params.key?(:enabled)

      if @subscription.save
        # Trigger a sync if enabled
        CalendarSyncJob.perform_later(@subscription.id) if @subscription.enabled?
        redirect_to my_calendar_sync_path, notice: "Calendar sync settings updated."
      else
        redirect_to my_calendar_sync_path, alert: @subscription.errors.full_messages.join(", ")
      end
    end

    def disconnect
      @subscription.destroy
      redirect_to my_calendar_sync_path, notice: "Calendar disconnected successfully."
    end

    def sync_now
      subscription = @person.calendar_subscriptions.find(params[:id])
      CalendarSyncJob.perform_later(subscription.id)
      redirect_to my_calendar_sync_path, notice: "Sync started. Your events will be updated shortly."
    end

    private

    def set_person
      @person = Current.user.person
    end

    def set_subscription
      @subscription = @person.calendar_subscriptions.find(params[:id])
    end

    def build_sync_entities
      entities = []

      if params[:sync_entities].is_a?(Array)
        params[:sync_entities].each do |entity_key|
          if entity_key == "person"
            entities << { "type" => "Person", "id" => @person.id }
          elsif entity_key.start_with?("group_")
            group_id = entity_key.gsub("group_", "").to_i
            if @person.groups.exists?(group_id)
              entities << { "type" => "Group", "id" => group_id }
            end
          end
        end
      end

      entities
    end

    def handle_google_callback
      token_data = CalendarSync::GoogleService.exchange_code_for_tokens(
        code: params[:code],
        redirect_uri: my_calendar_oauth_callback_url
      )

      if token_data["access_token"]
        email = CalendarSync::GoogleService.get_user_email(token_data["access_token"])

        subscription = @person.calendar_subscriptions.find_or_initialize_by(provider: "google")
        subscription.access_token = token_data["access_token"]
        subscription.refresh_token = token_data["refresh_token"] if token_data["refresh_token"]
        subscription.token_expires_at = Time.current + token_data["expires_in"].to_i.seconds
        subscription.email = email
        subscription.calendar_id = "primary"
        subscription.sync_scope ||= "assigned"
        subscription.sync_entities = [ { "type" => "Person", "id" => @person.id } ] if subscription.sync_entities.blank?
        subscription.enabled = true

        if subscription.save
          CalendarSyncJob.perform_later(subscription.id)
          redirect_to my_calendar_sync_path, notice: "Google Calendar connected successfully!"
        else
          redirect_to my_calendar_sync_path, alert: subscription.errors.full_messages.join(", ")
        end
      else
        redirect_to my_calendar_sync_path, alert: "Failed to connect Google Calendar: #{token_data['error_description']}"
      end
    end
  end
end
