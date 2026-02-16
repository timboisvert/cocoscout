# frozen_string_literal: true

class CredentialHealthCheckJob < ApplicationJob
  queue_as :low

  # Run daily to check all provider credentials
  def perform(provider_id = nil)
    if provider_id
      check_single_provider(provider_id)
    else
      check_all_providers
    end
  end

  private

  def check_all_providers
    TicketingProvider.status_active.api_enabled.find_each do |provider|
      # Skip if checked recently (within 6 hours)
      next if provider.credentials_checked_at&.after?(6.hours.ago)

      check_single_provider(provider.id)
    end
  end

  def check_single_provider(provider_id)
    provider = TicketingProvider.find_by(id: provider_id)
    return unless provider
    return if provider.manual_only?

    Rails.logger.info "[CredentialHealthCheck] Checking provider #{provider.id} (#{provider.name})"

    result = provider.validate_credentials!

    if result[:success]
      Rails.logger.info "[CredentialHealthCheck] Provider #{provider.id} credentials valid"
    else
      Rails.logger.warn "[CredentialHealthCheck] Provider #{provider.id} credentials INVALID: #{result[:error]}"

      # Mark all active listings as auth_expired
      provider.ticket_listings.where(status: %w[live ready pending_sync]).find_each do |listing|
        listing.update!(status: :auth_expired)
      end

      # TODO: Send notification to org admins about expired credentials
    end
  rescue StandardError => e
    Rails.logger.error "[CredentialHealthCheck] Error checking provider #{provider_id}: #{e.message}"
  end
end
