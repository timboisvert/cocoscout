# frozen_string_literal: true

class AddStatusToCastAssignmentStages < ActiveRecord::Migration[8.1]
  def change
    add_column :cast_assignment_stages, :status, :integer, default: 0, null: false
  end
end
