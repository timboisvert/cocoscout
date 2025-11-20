class CreateGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :groups do |t|
      t.string :name, null: false
      t.text :bio
      t.string :email, null: false
      t.string :phone
      t.string :website
      t.string :public_key, null: false
      t.text :old_keys
      t.datetime :archived_at

      t.timestamps
    end

    add_index :groups, :public_key, unique: true
    add_index :groups, :archived_at
  end
end
