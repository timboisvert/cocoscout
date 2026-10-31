# frozen_string_literal: true

# Membership emails in the organization's frame: welcome (the card), the
# sign-in code, and the renewal reminder. Words from the seeded templates.
class TicketMembershipMailer < ApplicationMailer
  skip_before_action :attach_logo

  def welcome(membership)
    deliver(membership.organization, membership.holder_email, **render_words("ticket_membership_welcome", variables(membership)))
  end

  def renewal(membership)
    deliver(membership.organization, membership.holder_email, **render_words("ticket_membership_renewal", variables(membership)))
  end

  def code(organization, email, code)
    deliver(organization, email, **render_words("ticket_member_code", { organization_name: organization.name, code: code, minutes: (TicketBuyerVerification::TTL / 60).to_i.to_s }))
  end

  private

  def variables(membership)
    { first_name: membership.first_name, organization_name: membership.organization.name, level_name: membership.level.name,
      ends_on: membership.ends_on.strftime("%B %-d, %Y"), perks: membership.level.perk_words.to_sentence.presence || "the perks your organization lists",
      membership_url: tickets_membership_url(token: membership.token),
      members_url: tickets_members_url(org: TicketingProfile.for(membership.organization).slug) }
  end

  def render_words(key, variables)
    { subject: ContentTemplateService.render_subject(key, variables),
      body_html: ContentTemplateService.render_body(key, variables.transform_values { |value| ERB::Util.html_escape(value.to_s) }) }
  end

  def deliver(organization, to, subject:, body_html:)
    @storefront_organization = organization
    @body_html = body_html
    mail(to: to, subject: subject, from: email_address_with_name("info@cocoscout.com", "#{organization.name} via CocoScout"),
         reply_to: TicketingProfile.for(organization).support_email.presence) do |format|
      format.html { render html: @body_html.html_safe, layout: "mailer" }
    end
  end
end
