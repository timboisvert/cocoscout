# frozen_string_literal: true

module My
  # The warm welcome page a new staff member lands on from their invite email.
  # Walks them through onboarding: accept the role, set up how they get paid, and
  # add their initial availability. "Accepting" (acknowledge) is a distinct step
  # from connecting a bank — both are required before they're fully onboarded.
  class OnboardingController < ApplicationController
    before_action :require_user
    before_action :set_person
    before_action :set_staff_member

    def show
      @organization = @staff_member.organization
    end

    # "I'm in" — record that they've accepted onboarding, then re-evaluate whether
    # they're fully onboarded (needs a connected bank too).
    def acknowledge
      @staff_member.update!(acknowledged_at: Time.current) unless @staff_member.acknowledged?
      @staff_member.refresh_onboarding_state!
      redirect_to my_onboarding_path(@staff_member.organization_id), notice: "You're in — welcome aboard! A couple of quick things left below."
    end

    private

    def set_person
      @person = Current.user&.person
      return if @person

      redirect_to profile_path, alert: "Please finish setting up your profile first."
    end

    def set_staff_member
      @staff_member = OrganizationStaffMember.active
                                             .find_by(organization_id: params[:organization_id], person_id: @person.id)
      return if @staff_member

      redirect_to my_dashboard_path, alert: "We couldn't find that staff invitation for your account."
    end

    def require_user
      return if Current.user

      redirect_to signin_path, alert: "Please sign in to finish onboarding."
    end
  end
end
