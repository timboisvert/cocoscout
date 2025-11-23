class CreatePerformanceCredits < ActiveRecord::Migration[8.1]
  def change
    create_table :performance_credits do |t|
      t.references :profileable, polymorphic: true, null: false
      t.string :section_name, limit: 50
      t.string :title, limit: 200, null: false
      t.string :venue, limit: 200
      t.string :location, limit: 100
      t.string :role, limit: 100
      t.integer :year_start, null: false
      t.integer :year_end
      t.text :notes, limit: 1000
      t.string :link_url
      t.integer :position, default: 0, null: false

      t.timestamps
    end

    add_index :performance_credits, [:profileable_type, :profileable_id, :section_name, :position], name: 'index_performance_credits_on_profileable_and_section'
  end
end
