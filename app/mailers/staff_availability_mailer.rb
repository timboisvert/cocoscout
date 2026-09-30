# frozen_string_literal: true

# "Is your availability up to date?" to staff. The copy is rendered by
# StaffAvailabilityNudger from a content template (or the manager's edited
# draft) and passed in — there's no copy here.
class StaffAvailabilityMailer < ApplicationMailer
  def confirm_request(staff_member, to:, subject:, body:)
    @staff_member = staff_member
    return if to.blank?

    mail(to: to, subject: subject) do |format|
      format.html { render html: body.html_safe, layout: "mailer" }
    end
  end
end
