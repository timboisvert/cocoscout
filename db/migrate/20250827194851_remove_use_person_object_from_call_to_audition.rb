# frozen_string_literal: true

class RemoveUsePersonObjectFromCallToAudition < ActiveRecord::Migration[8.0]
  def change
    remove_column :call_to_auditions, :use_person_object
  end
end
