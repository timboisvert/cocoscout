# frozen_string_literal: true

class CreateContractors < ActiveRecord::Migration[8.0]
  def change
    create_table :contractors do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.string :email
      t.string :phone
      t.text :address
      t.text :notes
      t.timestamps
    end

    add_index :contractors, [ :organization_id, :name ]
  end
end
