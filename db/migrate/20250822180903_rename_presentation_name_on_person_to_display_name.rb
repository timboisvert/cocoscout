# frozen_string_literal: true

class RenamePresentationNameOnPersonToDisplayName < ActiveRecord::Migration[8.0]
  def change
    rename_column :people, :presentation_name, :display_name
  end
end
