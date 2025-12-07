# frozen_string_literal: true

class AddHeaderTextToCallToAudition < ActiveRecord::Migration[8.0]
  def change
    add_column :call_to_auditions, :header_text, :text
  end
end
