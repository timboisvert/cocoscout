class UpdatePayoutLineItemsUniqueIndex < ActiveRecord::Migration[8.1]
  def change
    # Remove the old unique index that doesn't account for individual allocations
    remove_index :show_payout_line_items, name: "idx_payout_line_items_unique_payee"

    # Add new unique index that includes is_individual_allocation
    # This allows the same person to have both a performer payout AND an individual allocation
    add_index :show_payout_line_items,
              [ :show_payout_id, :payee_type, :payee_id, :is_individual_allocation ],
              unique: true,
              name: "idx_payout_line_items_unique_payee"
  end
end
