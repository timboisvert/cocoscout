# frozen_string_literal: true

# The emails a theater gets about its CocoScout bills: the bill, and the receipt.
class AddCocoscoutBillTemplates < ActiveRecord::Migration[8.1]
  def up
    PlatformTemplates.ensure!(keys: %w[cocoscout_bill cocoscout_bill_paid])
  end

  def down
    ContentTemplate.where(key: %w[cocoscout_bill cocoscout_bill_paid]).destroy_all
  end
end
