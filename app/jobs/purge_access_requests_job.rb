# frozen_string_literal: true

# Access needs are kept only as long as the door needs them (accessibility
# plan §4): deleted 30 days after the show.
class PurgeAccessRequestsJob < ApplicationJob
  queue_as :default

  def perform
    TicketOrderAccessRequest.joins(ticket_order: { ticket_listing: :show })
                            .where(shows: { date_and_time: ...(TicketOrderAccessRequest::KEEP_FOR.ago) })
                            .find_each(&:destroy)
  end
end
