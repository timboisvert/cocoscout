class CreateProfileHeadshots < ActiveRecord::Migration[8.1]
  def change
    create_table :profile_headshots do |t|
      t.references :profileable, polymorphic: true, null: false
      t.string :category
      t.boolean :is_primary, default: false, null: false
      t.integer :position, default: 0, null: false

      t.timestamps
    end

    add_index :profile_headshots, [ :profileable_type, :profileable_id, :position ]
  end
end
