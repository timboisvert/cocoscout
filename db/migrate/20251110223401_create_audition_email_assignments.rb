# frozen_string_literal: true

class CreateAuditionEmailAssignments < ActiveRecord::Migration[8.1]
  def change
    create_table :audition_email_assignments do |t|
      t.references :call_to_audition, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.string :email_group_id

      t.timestamps
    end
  end
end
