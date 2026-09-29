# frozen_string_literal: true

# Tax-form emails to staff (W-9 requests and reminders). The copy is rendered by
# StaffW9Requester from a content template (or the manager's edited draft) and
# passed in — there's no copy here.
class StaffTaxFormMailer < ApplicationMailer
  def w9_request(staff_member, to:, subject:, body:)
    @staff_member = staff_member
    return if to.blank?

    mail(to: to, subject: subject) do |format|
      format.html { render html: body.html_safe, layout: "mailer" }
    end
  end

  # "Your 1099 is ready" — the link inside opens the PDF from My Payments;
  # the PDF is deliberately not attached (avoids inboxing tax info).
  def form_1099_ready(form, to:, subject:, body:)
    @form = form
    return if to.blank?

    mail(to: to, subject: subject) do |format|
      format.html { render html: body.html_safe, layout: "mailer" }
    end
  end
end
