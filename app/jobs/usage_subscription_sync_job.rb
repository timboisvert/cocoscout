# frozen_string_literal: true

# Cancels an org's usage subscription the moment it stops paying for usage (a
# superadmin comped its usage, or its Pro plan ended), instead of waiting for
# the nightly reconciliation.
class UsageSubscriptionSyncJob < ApplicationJob
  queue_as :default

  def perform(organization_id)
    organization = Organization.find_by(id: organization_id)
    StaffMeterService.sync_usage_subscription!(organization) if organization
  end
end
