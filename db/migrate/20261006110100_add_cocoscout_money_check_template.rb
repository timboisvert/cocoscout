# frozen_string_literal: true

# The email superadmins get when the daily money check needs a look.
class AddCocoscoutMoneyCheckTemplate < ActiveRecord::Migration[8.1]
  def up
    PlatformTemplates.ensure!(keys: %w[cocoscout_money_check])
  end

  def down
    ContentTemplate.where(key: "cocoscout_money_check").destroy_all
  end
end
