# frozen_string_literal: true

# The waitlist's emails, in the organization's frame like a buyer's ticket
# emails: you're on the list, seats are yours for half an hour, the offer
# passed, and a note from the box office. Words from the seeded templates.
class TicketWaitlistMailer < ApplicationMailer
  skip_before_action :attach_logo

  def joined(entry)
    words = render_words("ticket_waitlist_joined", variables(entry))
    deliver(entry, **words)
  end

  def offer(entry)
    order = entry.offer_order
    words = render_words("ticket_waitlist_offer", variables(entry).merge(
      checkout_url: tickets_checkout_url(token: order.token), offer_until: entry.offer_expires_at.strftime("%-l:%M %p"),
      minutes: ((entry.offer_expires_at - Time.current) / 60).ceil.to_s
    ))
    deliver(entry, **words)
  end

  def missed(entry)
    deliver(entry, **render_words("ticket_waitlist_missed", variables(entry)))
  end

  # The manager's edited draft, already filled in for this person.
  def note(entry, subject:, body:)
    deliver(entry, subject: subject, body_html: ActionController::Base.helpers.sanitize(body))
  end

  private

  def variables(entry)
    listing = entry.ticket_listing
    show = listing.show
    { first_name: entry.first_name, organization_name: listing.organization.name, show_title: listing.display_title,
      show_date: show.date_and_time.strftime("%A, %B %-d"), show_time: show.date_and_time.strftime("%-l:%M %p"),
      ticket_count: ActionController::Base.helpers.pluralize(entry.quantity, "ticket"),
      show_page_url: tickets_event_url(org: TicketingProfile.for(listing.organization).slug, event: listing.slug),
      waitlist_url: tickets_waitlist_url(token: entry.token) }
  end

  def render_words(key, variables)
    { subject: ContentTemplateService.render_subject(key, variables),
      body_html: ContentTemplateService.render_body(key, variables.transform_values { |value| ERB::Util.html_escape(value.to_s) }) }
  end

  def deliver(entry, subject:, body_html:)
    organization = entry.organization
    @storefront_organization = organization
    @body_html = body_html
    mail(to: entry.email, subject: subject, from: email_address_with_name("info@cocoscout.com", "#{organization.name} via CocoScout"),
         reply_to: TicketingProfile.for(organization).support_email.presence) do |format|
      format.html { render html: @body_html.html_safe, layout: "mailer" }
    end
  end
end
