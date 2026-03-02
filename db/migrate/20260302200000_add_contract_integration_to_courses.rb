# frozen_string_literal: true

class AddContractIntegrationToCourses < ActiveRecord::Migration[8.0]
  def change
    # Allow contracts to skip creating events (space-rental-only contracts)
    add_column :contracts, :skip_event_creation, :boolean, default: false, null: false

    # Allow course offerings to link to a contract
    add_reference :course_offerings, :contract, null: true, foreign_key: true
  end
end
