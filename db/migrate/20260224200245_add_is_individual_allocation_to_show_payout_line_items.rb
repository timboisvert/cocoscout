class AddIsIndividualAllocationToShowPayoutLineItems < ActiveRecord::Migration[8.1]
  def change
    add_column :show_payout_line_items, :is_individual_allocation, :boolean, default: false, null: false
  end
end
