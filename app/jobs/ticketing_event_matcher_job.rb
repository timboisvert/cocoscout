# frozen_string_literal: true

# Background job that runs intelligent matching between provider events and shows
# This keeps event-show mappings up to date as new shows and events are created
class TicketingEventMatcherJob < ApplicationJob
  queue_as :default

  def perform(organization_id = nil)
    if organization_id
      match_for_organization(organization_id)
    else
      match_all_organizations
    end
  end

  private

  def match_all_organizations
    Rails.logger.info "[TicketingEventMatcherJob] Starting matching for all organizations"

    count = 0
    Organization.joins(:ticketing_providers).distinct.find_each do |org|
      result = match_for_organization(org.id)
      count += result[:auto_linked]
    end

    Rails.logger.info "[TicketingEventMatcherJob] Auto-linked #{count} events across all orgs"
  end

  def match_for_organization(org_id)
    org = Organization.find_by(id: org_id)
    return { auto_linked: 0, needs_review: 0, no_match: 0 } unless org

    matcher = TicketingEventMatcherService.new(org)
    result = matcher.match_all_events

    if result[:auto_linked] > 0
      Rails.logger.info "[TicketingEventMatcherJob] Org #{org.id}: auto-linked #{result[:auto_linked]} events"
    end

    result
  rescue StandardError => e
    Rails.logger.error "[TicketingEventMatcherJob] Error for org #{org_id}: #{e.message}"
    { auto_linked: 0, needs_review: 0, no_match: 0, error: e.message }
  end
end
