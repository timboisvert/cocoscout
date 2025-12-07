# frozen_string_literal: true

class AddFormReviewedToCallToAuditions < ActiveRecord::Migration[8.1]
  def change
    add_column :call_to_auditions, :form_reviewed, :boolean, default: false
  end
end
