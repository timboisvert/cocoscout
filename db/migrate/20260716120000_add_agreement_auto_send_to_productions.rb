# frozen_string_literal: true

class AddAgreementAutoSendToProductions < ActiveRecord::Migration[8.1]
  def change
    # How performers receive this production's agreement.
    # false (default) = producer sends manually; true = automatically request a
    # signature the moment a person is added to the production's talent pool.
    add_column :productions, :agreement_auto_send, :boolean, default: false, null: false
  end
end
