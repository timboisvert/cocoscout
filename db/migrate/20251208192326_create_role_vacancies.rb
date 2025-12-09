class CreateRoleVacancies < ActiveRecord::Migration[8.1]
  def change
    create_table :role_vacancies do |t|
      t.references :show, null: false, foreign_key: true
      t.references :role, null: false, foreign_key: true
      t.integer :vacated_by_id
      t.datetime :vacated_at
      t.text :reason
      t.string :status, default: "open", null: false
      t.integer :filled_by_id
      t.datetime :filled_at
      t.datetime :closed_at
      t.integer :closed_by_id
      t.integer :created_by_id

      t.timestamps
    end

    add_index :role_vacancies, [:show_id, :role_id, :status]
    add_index :role_vacancies, :status
  end
end
