# frozen_string_literal: true

class RenameShowCastAssignment < ActiveRecord::Migration[8.0]
  def change
    rename_table :show_cast_assignments, :show_person_role_assignments
  end
end
