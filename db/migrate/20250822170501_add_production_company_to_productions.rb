# frozen_string_literal: true

class AddProductionCompanyToProductions < ActiveRecord::Migration[8.0]
  def change
    add_reference :productions, :production_company, null: false, foreign_key: true
  end
end
