# frozen_string_literal: true

# The Stripe dispute on an order, so the order page can link straight to it.
class AddStripeDisputeIdToTicketOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :ticket_orders, :stripe_dispute_id, :string
  end
end
