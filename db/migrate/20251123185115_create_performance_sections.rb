# frozen_string_literal: true

class CreatePerformanceSections < ActiveRecord::Migration[8.1]
  def change
    create_table :performance_sections do |t|
      t.references :profileable, polymorphic: true, null: false
      t.string :name, null: false
      t.integer :position, default: 0, null: false

      t.timestamps
    end

    add_index :performance_sections, %i[profileable_type profileable_id position]
    add_reference :performance_credits, :performance_section, foreign_key: true
  end
end
