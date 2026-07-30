# frozen_string_literal: true

class AddRequiredStaffAgreementToOrganizations < ActiveRecord::Migration[8.1]
  def change
    # The staff agreement (if any) this org requires its staff to sign before they
    # can work. Nil = no agreement required (the default / prior behavior).
    add_reference :organizations, :required_staff_agreement_template,
                  null: true, index: true
  end
end
