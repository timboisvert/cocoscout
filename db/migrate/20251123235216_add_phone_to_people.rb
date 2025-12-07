# frozen_string_literal: true

class AddPhoneToPeople < ActiveRecord::Migration[8.1]
  def change
    add_column :people, :phone, :string
  end
end
