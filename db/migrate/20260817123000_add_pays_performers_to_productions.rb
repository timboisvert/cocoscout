# frozen_string_literal: true

# Whether a production pays the people who perform in it at all. Off means no
# payout calculation, no payment-setup reminders, nothing to work out. On is
# the norm, so existing productions keep paying; a production that pays chooses
# a calculation separately.
class AddPaysPerformersToProductions < ActiveRecord::Migration[8.1]
  def change
    add_column :productions, :pays_performers, :boolean, null: false, default: true
  end
end
