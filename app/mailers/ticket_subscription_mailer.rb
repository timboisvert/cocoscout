# frozen_string_literal: true

# Subscription emails in the organization's frame: welcome (the seats and
# dates) and the invitation to renew. Words from the seeded templates.
class TicketSubscriptionMailer < ApplicationMailer
  skip_before_action :attach_logo

  def welcome(subscription)
    deliver(subscription, **render_words("ticket_subscription_welcome", variables(subscription)))
  end

  def renewal(subscription)
    pass = subscription.renewal_pass
    deliver(subscription, **render_words("ticket_subscription_renewal", variables(subscription).merge(
      new_pass_name: pass&.name.to_s, closes_on: pass&.renewal_closes_at&.strftime("%B %-d, %Y").to_s
    )))
  end

  private

  def variables(subscription)
    { first_name: subscription.first_name, organization_name: subscription.organization.name, pass_name: subscription.ticket_pass.name,
      seats: subscription.seat_labels.to_sentence, show_count: subscription.ticket_pass.pass_shows.size.to_s,
      subscription_url: tickets_subscription_url(token: subscription.token) }
  end

  def render_words(key, variables)
    { subject: ContentTemplateService.render_subject(key, variables),
      body_html: ContentTemplateService.render_body(key, variables.transform_values { |value| ERB::Util.html_escape(value.to_s) }) }
  end

  def deliver(subscription, subject:, body_html:)
    organization = subscription.organization
    @storefront_organization = organization
    @body_html = body_html
    mail(to: subscription.buyer_email, subject: subject, from: email_address_with_name("info@cocoscout.com", "#{organization.name} via CocoScout"),
         reply_to: TicketingProfile.for(organization).support_email.presence) do |format|
      format.html { render html: @body_html.html_safe, layout: "mailer" }
    end
  end
end
