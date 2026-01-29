class CreateDemoUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :demo_users do |t|
      t.string :email, null: false
      t.string :name
      t.text :notes
      t.bigint :created_by_id

      t.timestamps
    end
    add_index :demo_users, :email, unique: true
    add_foreign_key :demo_users, :users, column: :created_by_id, on_delete: :nullify
  end
end
