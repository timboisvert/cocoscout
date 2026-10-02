# frozen_string_literal: true

# Sends one Ticketing notice (TicketingNotifier) off the request thread.
class TicketingNotificationJob < ApplicationJob
  queue_as :default

  def perform(organization_id, kind, variables, about_type = "", about_id = 0, occasion = "", once = false)
    organization = Organization.find_by(id: organization_id)
    return unless organization

    TicketingNotifier.deliver(organization, kind, variables, about_type: about_type, about_id: about_id, occasion: occasion, once: once)
  end
end
