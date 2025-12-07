# frozen_string_literal: true

class AddPublicKeyToPeople < ActiveRecord::Migration[8.1]
  def change
    add_column :people, :public_key, :string
    add_column :people, :old_keys, :text

    add_index :people, :public_key, unique: true
  end
end
