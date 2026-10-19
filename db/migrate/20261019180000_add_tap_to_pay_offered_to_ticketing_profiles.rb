# frozen_string_literal: true

# Tap to Pay on iPhone is CocoScout's to offer while it's new (Tim,
# 2026-10-19): an organization it's offered to sees it on Ticketing
# settings → Door and switches it on or off there (tap_to_pay). A
# superadmin sees it everywhere, and switching it on offers it from then on.
class AddTapToPayOfferedToTicketingProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :ticketing_profiles, :tap_to_pay_offered, :boolean, null: false, default: false
  end
end
