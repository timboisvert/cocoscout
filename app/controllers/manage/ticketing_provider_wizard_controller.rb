# frozen_string_literal: true

module Manage
  class TicketingProviderWizardController < Manage::ManageController
    before_action :set_wizard_state, except: [ :select_provider ]
    before_action :set_provider, only: [ :configure_webhooks, :save_webhooks, :test_connection, :complete ]

    # Step 1: Select provider type
    def select_provider
      # Clear any previous wizard state
      session.delete(:ticketing_wizard)
    end

    # Step 2a: Ticket Tailor credentials
    def ticket_tailor_credentials
      unless session.dig(:ticketing_wizard, :provider_type) == "ticket_tailor"
        session[:ticketing_wizard] = { provider_type: "ticket_tailor", step: "credentials" }
      end
      @provider = Current.organization.ticketing_providers.build(provider_type: "ticket_tailor")
    end

    def save_ticket_tailor_credentials
      @provider = Current.organization.ticketing_providers.build(ticket_tailor_params)
      @provider.provider_type = "ticket_tailor"

      if @provider.save
        session[:ticketing_wizard][:provider_id] = @provider.id
        session[:ticketing_wizard][:step] = "webhooks"
        redirect_to manage_ticketing_provider_wizard_configure_webhooks_path
      else
        render :ticket_tailor_credentials, status: :unprocessable_entity
      end
    end

    # Step 2b: Eventbrite credentials (OAuth or API key)
    def eventbrite_credentials
      unless session.dig(:ticketing_wizard, :provider_type) == "eventbrite"
        session[:ticketing_wizard] = { provider_type: "eventbrite", step: "credentials" }
      end
      @provider = Current.organization.ticketing_providers.build(provider_type: "eventbrite")
    end

    def save_eventbrite_credentials
      @provider = Current.organization.ticketing_providers.build(eventbrite_params)
      @provider.provider_type = "eventbrite"

      if @provider.save
        session[:ticketing_wizard][:provider_id] = @provider.id
        session[:ticketing_wizard][:step] = "webhooks"
        redirect_to manage_ticketing_provider_wizard_configure_webhooks_path
      else
        render :eventbrite_credentials, status: :unprocessable_entity
      end
    end

    # Step 3: Configure webhooks
    def configure_webhooks
      @webhook_url = ticketing_webhook_url(@provider)
    end

    def save_webhooks
      if @provider.update(webhook_params)
        session[:ticketing_wizard][:step] = "test"
        redirect_to manage_ticketing_provider_wizard_test_connection_path
      else
        @webhook_url = ticketing_webhook_url(@provider)
        render :configure_webhooks, status: :unprocessable_entity
      end
    end

    # Step 4: Test connection
    def test_connection
      @test_result = nil
    end

    def run_test
      @provider = Current.organization.ticketing_providers.find(session.dig(:ticketing_wizard, :provider_id))
      @test_result = @provider.test_connection

      if @test_result[:success]
        @provider.update(credentials_valid: true, last_credentials_check: Time.current)
        session[:ticketing_wizard][:step] = "complete"
      else
        @provider.update(credentials_valid: false, last_credentials_check: Time.current)
      end

      @webhook_url = ticketing_webhook_url(@provider)
      render :test_connection
    end

    # Step 5: Complete
    def complete
      # Clean up wizard state
      session.delete(:ticketing_wizard)
      redirect_to manage_ticketing_provider_path(@provider), notice: "#{@provider.name} connected successfully!"
    end

    private

    def set_wizard_state
      @wizard_state = session[:ticketing_wizard] || {}
    end

    def set_provider
      provider_id = session.dig(:ticketing_wizard, :provider_id)
      unless provider_id
        redirect_to manage_ticketing_provider_wizard_select_path, alert: "Please start the setup process again."
        return
      end
      @provider = Current.organization.ticketing_providers.find(provider_id)
    end

    def ticket_tailor_params
      params.require(:ticketing_provider).permit(:name, :api_key)
    end

    def eventbrite_params
      params.require(:ticketing_provider).permit(:name, :api_key)
    end

    def webhook_params
      params.require(:ticketing_provider).permit(:webhook_secret)
    end

    def ticketing_webhook_url(provider)
      # Generate the webhook URL for this provider
      Rails.application.routes.url_helpers.ticketing_webhook_url(
        provider.webhook_endpoint_token,
        host: request.host,
        protocol: request.protocol
      )
    rescue StandardError
      "#{request.base_url}/webhooks/ticketing/#{provider.webhook_endpoint_token}"
    end
  end
end
