# frozen_string_literal: true

# Returning part of a pass prices what the buyer keeps at its regular price
# (Tim, 2026-10-05: so nobody buys a pass for the discount and returns half).
# The refund remembers which kept tickets went back to regular and by how much.
class AddRepricingToTicketRefunds < ActiveRecord::Migration[8.1]
  def change
    add_column :ticket_refunds, :repriced_cents, :integer, null: false, default: 0
    add_column :ticket_refunds, :repriced, :jsonb, null: false, default: []
  end
end
