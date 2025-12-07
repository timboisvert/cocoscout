# frozen_string_literal: true

class CreateCastRoles < ActiveRecord::Migration[8.0]
  def change
    create_table :cast_roles do |t|
      t.references :cast, null: false, foreign_key: true
      t.string :name

      t.timestamps
    end
  end
end
