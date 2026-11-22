# frozen_string_literal: true

# The words of a performer's W-9 request and its reminder
# (PerformerTaxTemplates), seeded so they exist wherever the table does.
class SeedPerformerTaxTemplates < ActiveRecord::Migration[8.1]
  def up
    PerformerTaxTemplates.ensure!
  end

  def down
    ContentTemplate.where(key: PerformerTaxTemplates::TEMPLATES.map { |spec| spec[:key] }).delete_all
  end
end
