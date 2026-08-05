# frozen_string_literal: true

# Whether a catalog service is booked once per contract or once per event.
# A booth tech is per-event (pick which booked dates want one, set hours per
# date); a one-off cleaning fee is per-contract.
class AddBookingModeToContractServiceOptions < ActiveRecord::Migration[8.1]
  def change
    add_column :contract_service_options, :booking_mode, :string, default: "once", null: false
  end
end
