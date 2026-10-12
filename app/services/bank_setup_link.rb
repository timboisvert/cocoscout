# frozen_string_literal: true

# Emails a payee their own bank setup link (Tim, 2026-10-12). The link opens
# Stripe bank onboarding without signing in, so it goes only to the payee's
# address on file; managers press Send and never see or copy it, or they
# could open it and connect their own bank to someone else's payouts.
module BankSetupLink
  class Error < StandardError; end

  module_function

  def send!(organization:, payee:, by: nil)
    email = payee.email.to_s.strip
    raise Error, "#{payee.name} has no email address to send it to." if email.blank?

    url = Rails.application.routes.url_helpers.payee_onboarding_url(
      token: PayeeOnboardingToken.generate(payee), **ActionMailer::Base.default_url_options
    )
    first_name = payee.try(:first_name).presence || payee.name.to_s.split.first
    AppMailer.with(template_key: "payee_bank_setup_link", to: email,
                   variables: { "first_name" => first_name, "organization_name" => organization.name, "setup_url" => url })
             .send_template.deliver_later
    BankSetupEmail.create!(organization: organization, payee: payee, email: email, sent_by: by)
  end
end
