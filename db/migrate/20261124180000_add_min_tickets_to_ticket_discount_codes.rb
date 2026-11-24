# frozen_string_literal: true

# A discount code can require a minimum number of tickets on the order
# (Tim, 2026-11-24). Empty means no minimum, which is every code so far.
class AddMinTicketsToTicketDiscountCodes < ActiveRecord::Migration[8.1]
  def change
    add_column :ticket_discount_codes, :min_tickets, :integer
  end
end
