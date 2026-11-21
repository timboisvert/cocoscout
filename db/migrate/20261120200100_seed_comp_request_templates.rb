# frozen_string_literal: true

# The words of the notifications about requests for more comps
# (CompRequestTemplates), seeded so they exist wherever the table does.
class SeedCompRequestTemplates < ActiveRecord::Migration[8.1]
  def up
    CompRequestTemplates.ensure!
  end

  def down
    ContentTemplate.where(key: CompRequestTemplates::TEMPLATES.map { |spec| spec[:key] }).delete_all
  end
end
