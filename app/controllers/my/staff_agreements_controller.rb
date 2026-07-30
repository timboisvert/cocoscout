# frozen_string_literal: true

module My
  # Retroactive staff-agreement signing. When an org turns on (or updates the
  # version of) a required staff agreement, existing staff are prompted on their
  # own pages to sign it "to keep working." The onboarding #acknowledge action
  # can't do this — it's guarded by `unless acknowledged?` and so can never record
  # a fresh agreement version for someone already onboarded — so signing lives here.
  class StaffAgreementsController < ApplicationController
    before_action :require_user

    def sign
      member = find_membership
      return unless member

      unless member.needs_to_sign_agreement?
        return redirect_back(fallback_location: my_shifts_path,
                             notice: "You're all set — nothing to sign for #{member.organization.name}.")
      end

      template = member.required_agreement_template
      member.update!(
        staff_agreement_template: template,
        agreed_agreement_version: template.version,
        # Signing retroactively also counts as accepting onboarding if they hadn't.
        acknowledged_at: member.acknowledged_at || Time.current
      )
      member.refresh_onboarding_state!

      redirect_back fallback_location: my_shifts_path,
                    notice: "Thanks — your agreement with #{member.organization.name} is signed."
    end

    private

    # The caller's active staff membership at the given org, matched across every
    # Person on their account (the prompt is computed the same way).
    def find_membership
      person_ids = Current.user.people.active.pluck(:id)
      member = OrganizationStaffMember.active
                                      .find_by(organization_id: params[:organization_id], person_id: person_ids)
      return member if member

      redirect_back(fallback_location: my_shifts_path,
                    alert: "We couldn't find that staff agreement for your account.")
      nil
    end

    def require_user
      return if Current.user

      redirect_to signin_path, alert: "Please sign in first."
    end
  end
end
