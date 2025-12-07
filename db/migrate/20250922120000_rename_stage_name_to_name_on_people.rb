# frozen_string_literal: true

class RenameStageNameToNameOnPeople < ActiveRecord::Migration[8.0]
  def change
    rename_column :people, :stage_name, :name
  end
end
