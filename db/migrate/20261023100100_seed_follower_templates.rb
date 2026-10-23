# frozen_string_literal: true

# The words around mailing lists (FollowerTemplates).
class SeedFollowerTemplates < ActiveRecord::Migration[8.1]
  def up
    FollowerTemplates.ensure!
  end

  def down
    ContentTemplate.where(key: FollowerTemplates::TEMPLATES.map { |t| t[:key] }).delete_all
  end
end
