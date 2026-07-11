class CreateDepartments < ActiveRecord::Migration[8.1]
  def change
    create_table :departments do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name
      t.integer :position

      t.timestamps
    end
  end
end
