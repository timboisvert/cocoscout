# frozen_string_literal: true

# A gift certificate's recipient hears what it's worth, what it's good for
# and how to spend it, from the ticket_gift_certificate_issued template.
class TicketGiftCertificateMailer < ApplicationMailer
  skip_before_action :attach_logo

  def issued(certificate)
    organization = certificate.organization
    @storefront_organization = organization
    profile = TicketingProfile.for(organization)
    variables = {
      first_name: certificate.recipient_name.to_s.split.first.presence || "there",
      organization_name: organization.name,
      amount: ActiveSupport::NumberHelper.number_to_currency(certificate.amount_cents / 100.0),
      code: certificate.code,
      good_for: certificate.scope == "any" ? "any show #{organization.name} sells tickets to" : certificate.good_for_words,
      box_office_url: tickets_box_office_url(org: profile.slug)
    }
    subject = ContentTemplateService.render_subject("ticket_gift_certificate_issued", variables)
    @body_html = ContentTemplateService.render_body("ticket_gift_certificate_issued", variables.transform_values { |value| ERB::Util.html_escape(value.to_s) })
    mail(to: certificate.recipient_email, subject: subject,
         from: email_address_with_name("info@cocoscout.com", "#{organization.name} via CocoScout"),
         reply_to: profile.support_email.presence) do |format|
      format.html { render html: @body_html.html_safe, layout: "mailer" }
    end
  end
end
