# frozen_string_literal: true

module Manage
  # Organization settings → Integrations → Square (plan §9.3): connect with
  # Square's own sign-in, map its locations and categories to ours, choose
  # what comes in, pull now, read the pull log, disconnect. The owner's and
  # managers' page, like the rest of the organization's settings.
  class IntegrationsController < Manage::ManageController
    before_action :set_organization, except: :callback
    before_action :ensure_user_can_manage, except: :callback
    before_action :set_integration, only: %i[square update pull disconnect]

    def square
      @pulls = @integration&.register_pulls&.recent&.limit(12) || []
      @locations = @organization.locations.order(:name)
      @recent_days = @integration ? @integration.register_days.order(business_date: :desc).limit(7) : []
    end

    # "Connect with Square": off to Square's sign-in; the state ties the
    # answer back to this organization and this session.
    def connect
      return redirect_to manage_organization_square_path(@organization), alert: "Square is not set up on this server yet." unless SquareApi.configured?

      state = SecureRandom.hex(16)
      session[:square_oauth] = { "state" => state, "organization_id" => @organization.id }
      redirect_to SquareApi.authorize_url(state: state), allow_other_host: true
    end

    def callback
      pending = session.delete(:square_oauth) || {}
      organization = Current.user.accessible_organizations.find_by(id: pending["organization_id"])
      return redirect_to manage_organizations_path, alert: "That Square sign-in did not match. Try connecting again." if organization.nil? || params[:state].blank? || params[:state] != pending["state"]
      return redirect_to section_manage_organization_path(organization, section: "integrations"), alert: "Square did not connect: #{params[:error_description].presence || params[:error]}" if params[:error].present?

      tokens = SquareApi.exchange_code(params[:code], redirect_uri: manage_square_callback_url)
      integration = organization.integrations.find_or_initialize_by(provider: "square")
      integration.connect!(tokens: tokens.slice("access_token", "refresh_token", "expires_at", "merchant_id"), by: Current.user)
      SquareSync.refresh_catalog!(integration)
      yesterday = SettlementDay.day_for(organization, Time.current) - 1
      SquarePullJob.perform_later(integration.id, from: yesterday - 6, to: yesterday, trigger: "manual")
      redirect_to manage_organization_square_path(organization), notice: "Connected to Square. Say which locations are yours, and the last week is on its way."
    rescue SquareApi::Error => e
      redirect_to section_manage_organization_path(organization, section: "integrations"), alert: "Square did not connect: #{e.message}"
    end

    def update
      return redirect_to manage_organization_square_path(@organization), alert: "Connect Square first." unless @integration

      settings = @integration.settings.dup
      settings["location_map"] = params.fetch(:location_map, {}).permit!.to_h.transform_values(&:to_s) if params.key?(:location_map)
      settings["category_map"] = params.fetch(:category_map, {}).permit!.to_h.transform_values(&:to_s) if params.key?(:category_map)
      settings["brings"] = Integration::BRINGS.keys.index_with { |k| params.dig(:brings, k) == "1" } if params.key?(:brings)
      @integration.update!(settings: settings)
      # Mapped locations change which register days count: refresh their link.
      @integration.register_days.find_each { |d| d.update_columns(location_id: @integration.our_location_id(d.external_location_id)) }
      redirect_to manage_organization_square_path(@organization), notice: "Saved."
    end

    def pull
      return redirect_to manage_organization_square_path(@organization), alert: "Connect Square first." unless @integration

      today = SettlementDay.day_for(@organization, Time.current)
      SquarePullJob.perform_later(@integration.id, from: today - 7, to: today, trigger: "manual")
      redirect_to manage_organization_square_path(@organization), notice: "Pulling the last 7 days from Square. Give it a minute."
    end

    def disconnect
      if @integration
        begin
          SquareApi.revoke(@integration.access_token) if @integration.access_token.present?
        rescue SquareApi::Error => e
          Rails.logger.warn("[Square] revoke failed: #{e.message}")
        end
        @integration.disconnect!
      end
      redirect_to section_manage_organization_path(@organization, section: "integrations"), notice: "Square is disconnected. What it already brought in stays on the days it belongs to."
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
      @integration = @organization.integrations.square.first
    end
  end
end
