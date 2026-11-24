# frozen_string_literal: true

# The notice a production team gets when a performer gives up several acts in
# one show at once (VacancyTemplates; Tim, 2026-11-24). Rendering a missing
# key raises, so it's seeded here; content_templates is the only table read.
class SeedVacancyCreatedSeveralTemplate < ActiveRecord::Migration[8.1]
  def up
    VacancyTemplates.ensure!
  end

  def down
    ContentTemplate.where(key: VacancyTemplates::SEVERAL).delete_all
  end
end
