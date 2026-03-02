# frozen_string_literal: true

class AddContractorIdToContracts < ActiveRecord::Migration[8.0]
  def change
    add_reference :contracts, :contractor, foreign_key: true
  end
end
