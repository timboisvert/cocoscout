# frozen_string_literal: true

# A group leader's emails (Ticketing::GroupSales): seats held, tickets
# ready, seats about to be released, seats released. In the organization's
# frame like a buyer's ticket emails; words from the seeded templates.
class TicketGroupMailer < ApplicationMailer
  skip_before_action :attach_logo

  def booked(booking)
    deliver(booking, **render_words("ticket_group_booked", variables(booking)))
  end

  def tickets_ready(booking)
    deliver(booking, **render_words("ticket_group_tickets_ready", variables(booking)))
  end

  def release_warning(booking)
    deliver(booking, **render_words("ticket_group_release_warning", variables(booking)))
  end

  def released(booking)
    deliver(booking, **render_words("ticket_group_released", variables(booking)))
  end

  private

  def variables(booking)
    listing = booking.ticket_listing
    show = listing.show
    { first_name: booking.first_name, group_name: booking.name, organization_name: booking.organization.name,
      show_title: listing.display_title, show_date: show.date_and_time.strftime("%A, %B %-d"), show_time: show.date_and_time.strftime("%-l:%M %p"),
      seat_words: ActionController::Base.helpers.pluralize(booking.seats, "seat"),
      amount: ActiveSupport::NumberHelper.number_to_currency(booking.total_cents / 100.0),
      group_url: tickets_group_url(token: booking.token),
      due_date: booking.due_on.strftime("%B %-d"), release_date: booking.release_on.strftime("%B %-d"),
      show_page_url: tickets_event_url(org: TicketingProfile.for(booking.organization).slug, event: listing.slug) }
  end

  def render_words(key, variables)
    { subject: ContentTemplateService.render_subject(key, variables),
      body_html: ContentTemplateService.render_body(key, variables.transform_values { |value| ERB::Util.html_escape(value.to_s) }) }
  end

  def deliver(booking, subject:, body_html:)
    organization = booking.organization
    @storefront_organization = organization
    @body_html = body_html
    mail(to: booking.contact_email, subject: subject, from: email_address_with_name("info@cocoscout.com", "#{organization.name} via CocoScout"),
         reply_to: TicketingProfile.for(organization).support_email.presence) do |format|
      format.html { render html: @body_html.html_safe, layout: "mailer" }
    end
  end
end
