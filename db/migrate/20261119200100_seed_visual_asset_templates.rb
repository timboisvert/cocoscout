# frozen_string_literal: true

# The words of visual asset requests (VisualAssetTemplates), seeded so they
# exist wherever the table does.
class SeedVisualAssetTemplates < ActiveRecord::Migration[8.1]
  def up
    VisualAssetTemplates.ensure!
  end

  def down
    ContentTemplate.where(key: VisualAssetTemplates::TEMPLATES.map { |spec| spec[:key] }).delete_all
  end
end
