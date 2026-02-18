# frozen_string_literal: true

# Job to periodically verify ticketing provider connections are healthy.
# Runs on a schedule to ensure providers are properly configured and
# credentials are still valid.
#
# This job checks:
# - API credentials are valid (can connect)
# - Required permissions are present
# - Webhooks are properly configured (if enabled)
#
# Schedule: Every 15 minutes for active providers
#
class TicketingProviderHealthCheckJob < ApplicationJob
  queue_as :default

  # Check all active providers for a specific organization
  def perform(organization_id = nil)
    providers = if organization_id
      TicketingProvider.where(organization_id: organization_id)
    else
      TicketingProvider.all
    end

    providers.status_active.find_each do |provider|
      check_provider_health(provider)
    end
  end

  private

  def check_provider_health(provider)
    Rails.logger.info "[HealthCheck] Checking provider #{provider.id}: #{provider.name}"

    # Skip manual providers
    if provider.manual_only?
      provider.mark_credentials_valid!
      return
    end

    # Skip if recently checked (within last 5 minutes)
    if provider.credentials_checked_at&.> 5.minutes.ago
      Rails.logger.info "[HealthCheck] Provider #{provider.id} recently checked, skipping"
      return
    end

    # Test the connection
    result = provider.test_connection

    if result[:success]
      provider.mark_credentials_valid!
      Rails.logger.info "[HealthCheck] Provider #{provider.id}: Connection successful"

      # Check webhook configuration if enabled
      check_webhook_health(provider) if provider.webhook_enabled?
    else
      provider.mark_credentials_invalid!(result[:error])
      Rails.logger.warn "[HealthCheck] Provider #{provider.id}: Connection failed - #{result[:error]}"
    end
  rescue StandardError => e
    provider.mark_credentials_invalid!(e.message)
    Rails.logger.error "[HealthCheck] Provider #{provider.id}: Error - #{e.message}"
  end

  def check_webhook_health(provider)
    # Webhook is considered healthy if:
    # 1. We have a webhook secret configured
    # 2. We've received a webhook recently (optional - indicates actively working)

    unless provider.webhook_secret.present?
      Rails.logger.info "[HealthCheck] Provider #{provider.id}: Webhook enabled but no secret configured"
      return
    end

    # Check for recent webhook activity
    last_webhook = provider.webhook_logs.order(created_at: :desc).first

    if last_webhook.nil?
      Rails.logger.info "[HealthCheck] Provider #{provider.id}: No webhook activity recorded yet"
    elsif last_webhook.created_at < 24.hours.ago
      Rails.logger.info "[HealthCheck] Provider #{provider.id}: No webhook activity in 24 hours"
    else
      Rails.logger.info "[HealthCheck] Provider #{provider.id}: Webhook active, last received #{last_webhook.created_at}"
    end
  end
end
