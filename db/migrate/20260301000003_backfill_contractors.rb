# frozen_string_literal: true

class BackfillContractors < ActiveRecord::Migration[8.0]
  def up
    # Group contracts by contractor_name + organization_id to dedupe
    Contract.find_each do |contract|
      next if contract.contractor_id.present?
      next if contract.contractor_name.blank?

      # Find or create contractor for this organization
      contractor = Contractor.find_or_create_by!(
        organization_id: contract.organization_id,
        name: contract.contractor_name
      ) do |c|
        c.email = contract.contractor_email
        c.phone = contract.contractor_phone
        c.address = contract.contractor_address
      end

      # Update the contract to link to the contractor
      contract.update_column(:contractor_id, contractor.id)
    end
  end

  def down
    # No-op: we keep the contractor records but contracts still have their denormalized fields
  end
end
