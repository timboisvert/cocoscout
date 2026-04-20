# frozen_string_literal: true

class CreateDeviceTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :device_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token, null: false
      t.string :platform, null: false

      t.timestamps
    end

    add_index :device_tokens, [ :token, :platform ], unique: true
  end
end
