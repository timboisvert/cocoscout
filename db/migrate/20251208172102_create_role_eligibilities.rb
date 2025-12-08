class CreateRoleEligibilities < ActiveRecord::Migration[8.1]
  def change
    create_table :role_eligibilities do |t|
      t.references :role, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true

      t.timestamps
    end

    add_index :role_eligibilities, [ :role_id, :person_id ], unique: true
  end
end
