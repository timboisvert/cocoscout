# frozen_string_literal: true

class AddFieldsToProfile < ActiveRecord::Migration[8.0]
  def change
    add_column :people, :stage_name, :string
    add_column :people, :pronouns, :string
    remove_column :people, :first_name
    remove_column :people, :middle_name
    remove_column :people, :last_name
    remove_column :people, :suffix
    remove_column :people, :display_name
  end
end
