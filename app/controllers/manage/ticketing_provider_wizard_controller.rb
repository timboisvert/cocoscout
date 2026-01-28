# frozen_string_literal: true

module Manage
  class TicketingProviderWizardController < Manage::ManageController
    before_action :load_wizard_state

    # Step 1: Select Platform
    def platform
      @provider_types = Ticketing::ServiceFactory.available_providers
      @wizard_state[:provider_type] ||= nil
    end

    def save_platform
      @wizard_state[:provider_type] = params[:provider_type]

      unless Ticketing::ServiceFactory.available_providers.any? { |p| p[:id] == @wizard_state[:provider_type] }
        flash.now[:alert] = "Please select a platform"
        @provider_types = Ticketing::ServiceFactory.available_providers
        render :platform, status: :unprocessable_entity and return
      end

      save_wizard_state
      redirect_to manage_ticketing_wizard_credentials_path
    end

    # Step 2: Enter Credentials
    def credentials
      redirect_to manage_ticketing_wizard_path if @wizard_state[:provider_type].blank?

      @provider_type = @wizard_state[:provider_type]
      @provider_info = Ticketing::ServiceFactory.provider_info(@provider_type)
    end

    def save_credentials
      @wizard_state[:name] = params[:name].presence || default_provider_name
      @wizard_state[:api_key] = params[:api_key]

      if @wizard_state[:api_key].blank?
        flash.now[:alert] = "API key is required"
        @provider_type = @wizard_state[:provider_type]
        @provider_info = Ticketing::ServiceFactory.provider_info(@provider_type)
        render :credentials, status: :unprocessable_entity and return
      end

      save_wizard_state
      redirect_to manage_ticketing_wizard_test_path
    end

    # Step 3: Test Connection
    def test
      redirect_to manage_ticketing_wizard_path if @wizard_state[:provider_type].blank?

      @provider_type = @wizard_state[:provider_type]
      @provider_info = Ticketing::ServiceFactory.provider_info(@provider_type)
      @connection_result = nil

      # Build a temporary provider to test
      @temp_provider = Current.organization.ticketing_providers.new(
        provider_type: @wizard_state[:provider_type],
        name: @wizard_state[:name],
        api_key: @wizard_state[:api_key]
      )

      begin
        result = Ticketing::SyncCoordinator.new(@temp_provider).test_connection
        @connection_result = result
        @wizard_state[:test_passed] = result[:success]
        @wizard_state[:account_name] = result[:account_name]
        @wizard_state[:event_count] = result[:event_count]
        save_wizard_state
      rescue => e
        @connection_result = { success: false, error: e.message }
        @wizard_state[:test_passed] = false
        save_wizard_state
      end
    end

    def retry_test
      redirect_to manage_ticketing_wizard_test_path
    end

    # Step 4: Review and Create
    def review
      redirect_to manage_ticketing_wizard_path if @wizard_state[:provider_type].blank?
      redirect_to manage_ticketing_wizard_test_path unless @wizard_state[:test_passed]

      @provider_type = @wizard_state[:provider_type]
      @provider_info = Ticketing::ServiceFactory.provider_info(@provider_type)
    end

    def create_provider
      @ticketing_provider = Current.organization.ticketing_providers.new(
        provider_type: @wizard_state[:provider_type],
        name: @wizard_state[:name],
        api_key: @wizard_state[:api_key],
        provider_account_name: @wizard_state[:account_name],
        last_sync_status: "success",
        auto_sync_enabled: true,
        sync_interval_minutes: 60
      )

      if @ticketing_provider.save
        clear_wizard_state
        redirect_to manage_ticketing_provider_path(@ticketing_provider),
                    notice: "#{@ticketing_provider.name} connected successfully!"
      else
        flash.now[:alert] = @ticketing_provider.errors.full_messages.join(", ")
        @provider_type = @wizard_state[:provider_type]
        @provider_info = Ticketing::ServiceFactory.provider_info(@provider_type)
        render :review, status: :unprocessable_entity
      end
    end

    def cancel
      clear_wizard_state
      redirect_to manage_ticketing_providers_path,
                  notice: "Connection cancelled"
    end

    private

    def default_provider_name
      provider_info = Ticketing::ServiceFactory.provider_info(@wizard_state[:provider_type])
      provider_info&.dig(:name) || "Ticketing Provider"
    end

    def load_wizard_state
      @wizard_state = Rails.cache.read(wizard_cache_key) || {}
      @wizard_state = @wizard_state.with_indifferent_access
    end

    def save_wizard_state
      Rails.cache.write(wizard_cache_key, @wizard_state.to_h, expires_in: 24.hours)
    end

    def clear_wizard_state
      Rails.cache.delete(wizard_cache_key)
    end

    def wizard_cache_key
      "ticketing_wizard:#{Current.user.id}:#{Current.organization.id}"
    end
  end
end
