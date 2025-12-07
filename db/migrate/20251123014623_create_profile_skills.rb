# frozen_string_literal: true

class CreateProfileSkills < ActiveRecord::Migration[8.1]
  def change
    create_table :profile_skills do |t|
      t.references :profileable, polymorphic: true, null: false
      t.string :category, limit: 50, null: false
      t.string :skill_name, limit: 50, null: false

      t.timestamps
    end

    add_index :profile_skills, %i[profileable_type profileable_id category skill_name],
              unique: true,
              name: 'index_profile_skills_unique'
  end
end
