# frozen_string_literal: true

# Discount codes shared with the people who see a date's sales (Tim,
# 2026-10-17): the production team and the cast, the team only, or nobody.
# On by default: a code is usually made to be passed around.
class AddSharedWithToTicketDiscountCodes < ActiveRecord::Migration[8.1]
  def change
    add_column :ticket_discount_codes, :shared_with, :string, null: false, default: "team_and_cast"
  end
end
