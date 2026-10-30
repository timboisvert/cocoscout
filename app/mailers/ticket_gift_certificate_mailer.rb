# frozen_string_literal: true

# A gift certificate's recipient hears what it's worth, what it's good for
# and how to spend it, from the ticket_gift_certificate_issued template.
class TicketGiftCertificateMailer < ApplicationMailer
  TEMPLATE = "ticket_gift_certificate_issued"

  skip_before_action :attach_logo

  # The email as it will arrive, for the send preview and the send itself.
  def self.rendered(certificate)
    organization = certificate.organization
    profile = TicketingProfile.for(organization)
    variables = {
      first_name: certificate.recipient_name.to_s.split.first.presence || "there",
      organization_name: organization.name,
      amount: ActiveSupport::NumberHelper.number_to_currency(certificate.amount_cents / 100.0),
      code: certificate.code,
      good_for: certificate.scope == "any" ? "any show #{organization.name} sells tickets to" : certificate.good_for_words,
      box_office_url: Rails.application.routes.url_helpers.tickets_box_office_url(org: profile.slug, **ActionMailer::Base.default_url_options)
    }
    {
      subject: ContentTemplateService.render_subject(TEMPLATE, variables),
      body: ContentTemplateService.render_body(TEMPLATE, variables.transform_values { |value| ERB::Util.html_escape(value.to_s) }),
      reply_to: profile.support_email.presence
    }
  end

  def issued(certificate)
    organization = certificate.organization
    @storefront_organization = organization
    rendered = self.class.rendered(certificate)
    @body_html = rendered[:body]
    mail(to: certificate.recipient_email, subject: rendered[:subject],
         from: email_address_with_name("info@cocoscout.com", "#{organization.name} via CocoScout"),
         reply_to: rendered[:reply_to]) do |format|
      format.html { render html: @body_html.html_safe, layout: "mailer" }
    end
  end
end
