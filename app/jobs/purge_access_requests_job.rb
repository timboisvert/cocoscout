# frozen_string_literal: true

# Access needs are kept only as long as they're needed. A buyer's (plan §4)
# goes 30 days after the show; a performer's or crew member's (plan §3) goes
# when its audition cycle or production ends.
class PurgeAccessRequestsJob < ApplicationJob
  queue_as :default

  def perform
    TicketOrderAccessRequest.joins(ticket_order: { ticket_listing: :show })
                            .where(shows: { date_and_time: ...(TicketOrderAccessRequest::KEEP_FOR.ago) })
                            .find_each(&:destroy)

    AccessNeed.for_auditions.includes(:audition_cycle).find_each do |need|
      need.destroy if AccessNeed.cycle_over?(need.audition_cycle)
    end
    AccessNeed.for_productions.includes(:production).find_each do |need|
      need.destroy if AccessNeed.production_over?(need.production)
    end
  end
end
