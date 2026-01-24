# frozen_string_literal: true

class MakePayeeTypeNullableForGuests < ActiveRecord::Migration[8.1]
  def change
    # Make payee_type nullable for guest line items (guests don't have a payee record)
    change_column_null :show_payout_line_items, :payee_type, true
  end
end
