# frozen_string_literal: true

# Hourly: each production with ticketing on lists the shows its setup
# includes (ProductionTicketingDates), so new dates on the calendar join on
# their own. Also run for one production right after a show is added.
class ProductionTicketingDatesJob < ApplicationJob
  queue_as :default

  def perform(production_ticketing_id = nil)
    if production_ticketing_id
      production_ticketing = ProductionTicketing.find_by(id: production_ticketing_id)
      ProductionTicketingDates.sync!(production_ticketing) if production_ticketing
    else
      ProductionTicketingDates.sync_all!
    end
  end
end
