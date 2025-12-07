# frozen_string_literal: true

class AddProductionCompanyIdToLocations < ActiveRecord::Migration[7.0]
  def change
    add_reference :locations, :production_company, foreign_key: true
  end
end
