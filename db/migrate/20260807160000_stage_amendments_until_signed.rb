# frozen_string_literal: true

# A signature-requiring amendment is a proposal, not a fact. Until the
# counterparty signs it, the live contract must keep describing the deal
# actually in force — so the amendment rides on its version instead.
class StageAmendmentsUntilSigned < ActiveRecord::Migration[8.1]
  def change
    # The amend_data this version is proposing. Applied for real on execution.
    add_column :contract_versions, :staged_amendment, :jsonb
    # Overlaps were acknowledged when the amendment was staged; the apply on
    # signature has to honour that same acknowledgement.
    add_column :contract_versions, :force_overlap, :boolean, null: false, default: false
  end
end
