# frozen_string_literal: true

# The payout provider asks a payee for more about themselves as their pay
# grows (date of birth and the last four of the SSN once it reaches $3,000),
# and the setup form only asked for what was due then, so their pay would
# pause at that point. This remembers, from each account sync, that more is
# coming due, so My Payments can say so before it does (after-V1 #2).
class AddPayoutDetailsDueToPeople < ActiveRecord::Migration[8.1]
  def change
    add_column :people, :payout_details_due, :boolean, default: false, null: false
  end
end
