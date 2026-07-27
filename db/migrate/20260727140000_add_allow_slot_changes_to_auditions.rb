# frozen_string_literal: true

# Open sign-up: whether a performer may move to a different slot after booking.
# Default true (they can change); orgs can lock it so a booked slot is final.
class AddAllowSlotChangesToAuditions < ActiveRecord::Migration[8.1]
  def change
    add_column :audition_cycles, :allow_slot_changes, :boolean, null: false, default: true
  end
end
