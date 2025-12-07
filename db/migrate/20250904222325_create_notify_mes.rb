# frozen_string_literal: true

class CreateNotifyMes < ActiveRecord::Migration[8.0]
  def change
    create_table :notify_mes do |t|
      t.string :email

      t.timestamps
    end
  end
end
