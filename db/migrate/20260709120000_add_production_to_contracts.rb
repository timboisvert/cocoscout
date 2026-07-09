# frozen_string_literal: true

# Invert the production <-> contract relationship. A real-world production can be
# the subject of MANY contracts over time (each contract = more dates/space rentals),
# so a contract now belongs_to a production (contracts.production_id) and a production
# has_many contracts. The old productions.contract_id column is left in place
# (unused) so this is reversible and low-risk.
class AddProductionToContracts < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:contracts, :production_id)
      add_reference :contracts, :production, foreign_key: true, null: true, index: true
    end

    # Backfill: point each contract at the production it created. When a contract
    # created more than one (the course-husk bug), prefer the one that actually has
    # shows; fall back to the newest.
    Contract.reset_column_information
    Contract.find_each do |contract|
      productions = Production.where(contract_id: contract.id).to_a
      next if productions.empty?

      best = productions.max_by { |p| [ p.shows.count, p.id ] }
      contract.update_column(:production_id, best.id)
    end
  end

  def down
    remove_reference :contracts, :production
  end
end
