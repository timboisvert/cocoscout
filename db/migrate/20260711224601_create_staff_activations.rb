class CreateStaffActivations < ActiveRecord::Migration[8.1]
  def change
    create_table :staff_activations do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.date :billing_month, null: false
      t.datetime :first_notified_at

      t.timestamps
    end
    add_index :staff_activations, %i[organization_id person_id billing_month], unique: true,
              name: "idx_staff_activations_unique"
  end
end
