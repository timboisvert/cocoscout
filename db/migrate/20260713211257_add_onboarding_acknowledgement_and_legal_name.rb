# frozen_string_literal: true

class AddOnboardingAcknowledgementAndLegalName < ActiveRecord::Migration[8.1]
  def change
    # When the staff member acknowledged/accepted onboarding on their welcome
    # page. Onboarding is "completed" only once this is set AND their bank is
    # connected — the two are distinct steps.
    add_column :organization_staff_members, :acknowledged_at, :datetime

    # Full legal name used to pay someone officially — distinct from the Person's
    # display name, which may be a stage name (e.g. a burlesque performer).
    add_column :people, :legal_name, :string
  end
end
