# frozen_string_literal: true

class AddAgreementExemptToOrganizationStaffMembers < ActiveRecord::Migration[8.1]
  def change
    # This staff member is excused from signing the org's required staff agreement.
    add_column :organization_staff_members, :agreement_exempt, :boolean,
               null: false, default: false
  end
end
