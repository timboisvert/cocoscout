# frozen_string_literal: true

# Which lists a pass buyer ticked at checkout (Mailing lists, V1.1).
class AddFollowListIdsToTicketPurchases < ActiveRecord::Migration[8.1]
  def change
    add_column :ticket_purchases, :follow_list_ids, :jsonb, null: false, default: []
  end
end
