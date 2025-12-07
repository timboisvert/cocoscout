# frozen_string_literal: true

class AddSuccessTextToCallToAudition < ActiveRecord::Migration[8.0]
  def change
    add_column :call_to_auditions, :success_text, :text
  end
end
