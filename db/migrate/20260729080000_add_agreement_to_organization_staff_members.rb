# frozen_string_literal: true

# Records which employee agreement a staff member was asked to agree to, and the
# exact version they accepted during onboarding (so the accepted wording is
# traceable even if the template later changes).
class AddAgreementToOrganizationStaffMembers < ActiveRecord::Migration[8.1]
  def change
    add_reference :organization_staff_members, :staff_agreement_template, foreign_key: true, null: true
    add_column :organization_staff_members, :agreed_agreement_version, :integer
  end
end
