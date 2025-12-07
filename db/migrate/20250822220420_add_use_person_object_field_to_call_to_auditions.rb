# frozen_string_literal: true

class AddUsePersonObjectFieldToCallToAuditions < ActiveRecord::Migration[8.0]
  def change
    add_column :call_to_auditions, :use_person_object, :boolean, default: true
  end
end
