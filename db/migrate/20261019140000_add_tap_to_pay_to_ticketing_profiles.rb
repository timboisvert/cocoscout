# frozen_string_literal: true

# Tap to Pay on iPhone, organization by organization (Apple's "flagged
# release", 2026-10-19): off for everyone until Apple grants the publishing
# entitlement, then switched on per organization. The launch email and push
# go to the people who can sell at a door that has it.
class AddTapToPayToTicketingProfiles < ActiveRecord::Migration[8.1]
  def up
    add_column :ticketing_profiles, :tap_to_pay, :boolean, null: false, default: false
    TapToPayTemplates.ensure!
  end

  def down
    remove_column :ticketing_profiles, :tap_to_pay
  end
end
