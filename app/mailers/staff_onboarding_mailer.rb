# frozen_string_literal: true

# Invites a newly-added staff member to finish onboarding — create/access their
# CocoScout account and connect their bank so they can be paid. Uses the content
# template system when a "staff_onboarding_invite" template exists, and otherwise
# falls back to the built-in view (so it works before anyone customizes the copy).
class StaffOnboardingMailer < ApplicationMailer
  def invite(staff_member)
    @staff_member = staff_member
    @person = staff_member.person
    @organization = staff_member.organization
    @onboarding_url = my_payments_setup_url(**default_url_options)

    to = @person.email.presence || staff_member.personal_email
    return if to.blank?

    if ContentTemplateService.exists?("staff_onboarding_invite")
      rendered = ContentTemplateService.render("staff_onboarding_invite", template_vars)
      mail(to: to, subject: rendered[:subject]) do |format|
        format.html { render html: rendered[:body].html_safe, layout: "mailer" }
      end
    else
      @subject = "Complete your onboarding at #{@organization.name}"
      mail(to: to, subject: @subject)
    end
  end

  private

  def template_vars
    {
      first_name: @staff_member.preferred_first_name.presence || @staff_member.first_name.presence || @person&.name.to_s,
      organization_name: @organization.name,
      onboarding_url: @onboarding_url
    }
  end
end
