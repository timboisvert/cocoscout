# frozen_string_literal: true

class EnhanceTicketListingStates < ActiveRecord::Migration[8.0]
  def change
    # Enhanced sync tracking
    add_column :ticket_listings, :last_sync_attempt_at, :datetime
    add_column :ticket_listings, :sync_attempt_count, :integer, default: 0, null: false
    add_column :ticket_listings, :next_sync_at, :datetime

    # Manual listing workflow
    add_column :ticket_listings, :requires_manual_action, :boolean, default: false, null: false
    add_column :ticket_listings, :manual_action_completed_at, :datetime
    add_column :ticket_listings, :manual_action_notes, :text

    # Provider approval tracking
    add_column :ticket_listings, :submitted_at, :datetime
    add_column :ticket_listings, :approved_at, :datetime
    add_column :ticket_listings, :approval_status, :string

    # Data completeness tracking
    add_column :ticket_listings, :missing_fields, :jsonb, default: [], null: false
    add_column :ticket_listings, :provider_data_snapshot, :jsonb, default: {}, null: false

    # Last known external state
    add_column :ticket_listings, :external_status, :string
    add_column :ticket_listings, :external_last_modified_at, :datetime

    add_index :ticket_listings, :requires_manual_action
    add_index :ticket_listings, :next_sync_at
    add_index :ticket_listings, :approval_status
  end
end
