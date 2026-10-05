# frozen_string_literal: true

# The email that carries a theater's monthly CocoScout statement.
class AddOrgMonthlyStatementTemplate < ActiveRecord::Migration[8.1]
  def up
    PlatformTemplates.ensure!(keys: %w[org_monthly_statement])
  end

  def down
    ContentTemplate.where(key: "org_monthly_statement").destroy_all
  end
end
