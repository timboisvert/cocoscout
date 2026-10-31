# frozen_string_literal: true

# Advanced ticketing §1 (V1.4 step 4b): the email a buyer gets when the box
# office moves their seats.
class AddTicketSeatsChangedTemplate < ActiveRecord::Migration[8.1]
  def up
    TicketingTemplates.ensure!(keys: %w[ticket_seats_changed])
  end

  def down; end
end
