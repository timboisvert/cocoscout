# frozen_string_literal: true

class RenameProducerToOwnerInMics < ActiveRecord::Migration[8.1]
  def change
    rename_table :mic_producers, :mic_owners
    rename_column :mics, :lead_producer_user_id, :lead_owner_user_id
  end
end
