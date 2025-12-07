# frozen_string_literal: true

class AddEmailGroupIdToCastAssignmentStages < ActiveRecord::Migration[8.1]
  def change
    add_column :cast_assignment_stages, :email_group_id, :string
  end
end
