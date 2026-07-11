# frozen_string_literal: true

# Gusto-style employment profile for a staff member. Legal name parts live here
# (Person keeps a single display `name`). SSN/tax ID is intentionally NOT stored
# — Stripe Connect collects it during the worker's own onboarding.
class AddEmploymentFieldsToOrganizationStaffMembers < ActiveRecord::Migration[8.1]
  def change
    change_table :organization_staff_members, bulk: true do |t|
      t.string  :first_name
      t.string  :middle_initial
      t.string  :last_name
      t.string  :preferred_first_name
      t.string  :personal_email
      t.string  :title
      t.integer :hourly_rate_cents
      t.date    :start_date
      t.bigint  :manager_id
      t.string  :onboarding_state, null: false, default: "added"
    end

    add_index :organization_staff_members, :manager_id
    add_foreign_key :organization_staff_members, :organization_staff_members,
                    column: :manager_id, on_delete: :nullify
  end
end
