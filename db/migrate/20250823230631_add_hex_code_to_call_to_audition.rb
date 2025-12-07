# frozen_string_literal: true

class AddHexCodeToCallToAudition < ActiveRecord::Migration[8.0]
  def change
    add_column :call_to_auditions, :hex_code, :string
  end
end
