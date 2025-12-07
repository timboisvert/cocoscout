# frozen_string_literal: true

class AddNameAndNotesToLocation < ActiveRecord::Migration[8.0]
  def change
    add_column :locations, :name, :string
    add_column :locations, :notes, :text
  end
end
