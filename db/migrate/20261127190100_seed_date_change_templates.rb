# frozen_string_literal: true

# The words of what a date change sends that nothing sent before
# (DateChangeTemplates; Tim, 2026-11-27). Rendering a missing key raises, so
# they're seeded here; content_templates is the only table read.
class SeedDateChangeTemplates < ActiveRecord::Migration[8.1]
  def up
    DateChangeTemplates.ensure!
  end

  def down
    ContentTemplate.where(key: DateChangeTemplates::KEYS).delete_all
  end
end
