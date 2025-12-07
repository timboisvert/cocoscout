# frozen_string_literal: true

class CreateSocials < ActiveRecord::Migration[7.0]
  def change
    remove_column :people, :socials

    create_table :socials do |t|
      t.references :person, null: false, foreign_key: true
      t.string :platform, null: false
      t.string :handle, null: false
      t.timestamps
    end
  end
end
