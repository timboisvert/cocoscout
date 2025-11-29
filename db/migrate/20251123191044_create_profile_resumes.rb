class CreateProfileResumes < ActiveRecord::Migration[8.1]
  def change
    create_table :profile_resumes do |t|
      t.references :profileable, polymorphic: true, null: false
      t.string :name, null: false
      t.boolean :is_primary, default: false, null: false
      t.integer :position, default: 0, null: false

      t.timestamps
    end

    add_index :profile_resumes, [ :profileable_type, :profileable_id, :position ]
  end
end
