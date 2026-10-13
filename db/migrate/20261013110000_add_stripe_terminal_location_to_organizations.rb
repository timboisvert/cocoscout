# frozen_string_literal: true

# Tap to Pay on the door phone runs through Stripe Terminal, which wants every
# in-person payment tied to a Location: one per organization, made the first
# time it sells by tap (TapToPay.location_for).
class AddStripeTerminalLocationToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :stripe_terminal_location_id, :string
  end
end
