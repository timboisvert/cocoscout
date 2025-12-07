# frozen_string_literal: true

class AddPersonToUsers < ActiveRecord::Migration[8.0]
  def change
    add_reference :users, :person, foreign_key: true
  end
end
