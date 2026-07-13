# frozen_string_literal: true

# Invites a newly-added staff member to finish onboarding — create/access their
# CocoScout account and connect their bank so they can be paid. All copy comes
# from the "staff_onboarding_invite" content template: the caller (the inviter)
# renders it and passes the subject/body here; if not supplied, we render it too.
# There is deliberately no hardcoded fallback copy.
class StaffOnboardingMailer < ApplicationMailer
  # subject/body: the exact copy to send (already rendered from the template, e.g.
  # the reviewer's edited draft). When omitted, we render the template ourselves.
  def invite(staff_member, subject: nil, body: nil)
    @staff_member = staff_member
    @person = staff_member.person
    @organization = staff_member.organization

    to = @person.email.presence || staff_member.personal_email
    return if to.blank?

    if body.blank? || subject.blank?
      rendered = ContentTemplateService.render("staff_onboarding_invite", template_vars)
      subject = rendered[:subject]
      body = rendered[:body]
    end

    mail(to: to, subject: subject) do |format|
      format.html { render html: body.html_safe, layout: "mailer" }
    end
  end

  private

  def template_vars
    {
      first_name: @staff_member.preferred_first_name.presence || @staff_member.first_name.presence || @person&.name.to_s,
      organization_name: @organization.name,
      onboarding_url: my_onboarding_url(@organization.id, **default_url_options)
    }
  end
end
