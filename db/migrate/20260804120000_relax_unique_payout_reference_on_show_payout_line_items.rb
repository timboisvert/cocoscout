# frozen_string_literal: true

# One payout-run transfer settles EVERY show line item bundled into that
# payee's batch item ("a performer in four weekend shows ends up as one item
# with four contributions"), so multiple lines legitimately share one
# payout_reference_id. The unique index predates that bundling model and made
# settling the second line blow up. Traceability only needs a plain lookup.
class RelaxUniquePayoutReferenceOnShowPayoutLineItems < ActiveRecord::Migration[8.1]
  def change
    remove_index :show_payout_line_items, name: "index_show_payout_line_items_on_payout_reference_id"
    add_index :show_payout_line_items, :payout_reference_id,
              where: "payout_reference_id IS NOT NULL",
              name: "index_show_payout_line_items_on_payout_reference_id"
  end
end
