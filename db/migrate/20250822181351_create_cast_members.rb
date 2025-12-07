# frozen_string_literal: true

class CreateCastMembers < ActiveRecord::Migration[8.0]
  def change
    create_table :cast_members do |t|
      t.references :cast, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true

      t.timestamps
    end
  end
end
