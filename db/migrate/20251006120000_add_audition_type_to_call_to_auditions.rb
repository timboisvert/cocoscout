# frozen_string_literal: true

class AddAuditionTypeToCallToAuditions < ActiveRecord::Migration[7.0]
  def change
    add_column :call_to_auditions, :audition_type, :string, null: false, default: 'in_person'
  end
end
