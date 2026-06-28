# frozen_string_literal: true

class RemoveServicesFromContractDraftData < ActiveRecord::Migration[8.1]
  def up
    Contract.where("draft_data ? 'services'").find_each do |contract|
      contract.update_column(:draft_data, contract.draft_data.except("services"))
    end
  end

  def down
    # No-op: the removed services data is not recoverable.
  end
end
