# frozen_string_literal: true

# A buyer's emails about their order: their tickets (the confirmation, the
# reminder before the show, a show that moved, tickets moved to another
# date), refunds, and a canceled show. The words come
# from content templates; under the words of an email with tickets sits one
# QR code per ticket.
class TicketOrderMailer < ApplicationMailer
  def confirmation(order)
    deliver_tickets(order, **render_words("ticket_order_confirmation", self.class.ticket_variables(order)))
  end

  # A few days before the show (as many as the theater chose): the time,
  # the place and the tickets again, from the ticket_event_reminder template.
  # Mail apps' own unsubscribe button turns reminders off for this order.
  def reminder(order)
    show = order.ticket_listing.show
    location = show.location
    address = [ location&.address1, location&.city ].compact_blank.join(", ")
    stop_url = tickets_order_reminders_url(token: order.token)
    headers["List-Unsubscribe"] = "<#{tickets_order_stop_reminders_url(token: order.token)}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
    deliver_tickets(order, **render_words("ticket_event_reminder", self.class.ticket_variables(order).merge(
      when: self.class.when_words(show.date_and_time),
      address: address,
      directions_url: address.present? ? "https://www.google.com/maps/search/?api=1&query=#{ERB::Util.url_encode([ location.name, address ].join(', '))}" : "",
      door_note: order.ticket_listing.effective_door_note.to_s,
      stop_reminders_url: stop_url
    )))
  end

  # A show that moved: the manager's edited draft of the
  # ticket_event_changed template, {{variables}} filled for this buyer (what
  # they were told, and what it is now), with their tickets, which still work.
  def changed(order, subject:, body:)
    variables = TicketShowChange.variables(order)
    deliver_tickets(order, subject: ContentTemplate.interpolate(subject.to_s, variables),
                           body_html: self.class.paragraphs(ContentTemplate.interpolate(body.to_s, variables)))
  end

  # Tickets the theater moved to another date: the new tickets, the date they
  # were for, and the refunded difference when the new ones cost less (from
  # the ticket_order_moved template).
  def moved(exchange)
    order = exchange.to_order
    refund = exchange.ticket_refund
    refunded = refund&.status == "succeeded" ? ActiveSupport::NumberHelper.number_to_currency(refund.amount_cents / 100.0) : ""
    deliver_tickets(order, **render_words("ticket_order_moved", self.class.ticket_variables(order).merge(
      was: exchange.from_order.ticket_listing.show.date_and_time.strftime("%A, %B %-d at %-l:%M %p"),
      refund_amount: refunded
    )))
  end

  # The words every email with tickets in it can use.
  def self.ticket_variables(order)
    listing = order.ticket_listing
    show = listing.show
    count = order.tickets.count { |t| Ticket::SOLD_STATUSES.include?(t.status) }
    {
      first_name: order.buyer_name.to_s.split.first.presence || "there",
      organization_name: listing.organization.name,
      show_title: listing.display_title,
      show_date: show.date_and_time.strftime("%A, %B %-d"),
      show_time: show.date_and_time.strftime("%-l:%M %p"),
      venue: [ show.location&.name, show.location_space&.name ].compact.uniq.join(", "),
      ticket_count: ActionController::Base.helpers.pluralize(count, "ticket"),
      ticket_count_verb: count == 1 ? "is" : "are",
      order_code: order.code,
      order_url: routes.tickets_order_url(token: order.token, **url_options)
    }
  end

  # "tomorrow", "on Friday", or "on Friday, October 10" for further off.
  def self.when_words(time, today: Date.current)
    days = (time.to_date - today).to_i
    return "today" if days <= 0
    return "tomorrow" if days == 1
    return "on #{time.strftime('%A')}" if days < 7

    "on #{time.strftime('%A, %B %-d')}"
  end

  # Money back, from the ticket_order_refunded template.
  def refunded(refund)
    @order = refund.ticket_order
    rendered = render_words("ticket_order_refunded", self.class.variables_for(@order, refund))
    @body_html = rendered[:body_html]
    deliver_from_theater(rendered[:subject])
  end

  # A canceled show: the manager's edited draft of the ticket_event_canceled
  # template (plain text, {{variables}} filled per buyer).
  def canceled(refund, subject:, body:)
    @order = refund.ticket_order
    variables = self.class.variables_for(@order, refund)
    @body_html = self.class.paragraphs(ContentTemplate.interpolate(body.to_s, variables))
    deliver_from_theater(ContentTemplate.interpolate(subject.to_s, variables))
  end

  # The variables both refund emails fill in. A preview passes the amount and
  # count a refund would have, before there is one.
  def self.variables_for(order, refund = nil, amount_cents: refund&.amount_cents, ticket_count: refund&.ticket_ids&.size)
    listing = order.ticket_listing
    show = listing.show
    count = ticket_count || order.tickets.size
    {
      first_name: order.buyer_name.to_s.split.first.presence || "there",
      organization_name: listing.organization.name,
      show_title: listing.display_title,
      show_date: show.date_and_time.strftime("%A, %B %-d"),
      show_time: show.date_and_time.strftime("%-l:%M %p"),
      refund_amount: ActiveSupport::NumberHelper.number_to_currency(amount_cents.to_i / 100.0),
      ticket_count: ActionController::Base.helpers.pluralize(count, "ticket"),
      order_code: order.code,
      order_url: routes.tickets_order_url(token: order.token, **url_options)
    }
  end

  def self.routes
    Rails.application.routes.url_helpers
  end

  def self.url_options
    Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
  end

  # A template's HTML as the plain text a manager edits before a send to many
  # buyers: paragraphs separated by blank lines.
  def self.plain_text(html)
    text = html.to_s.gsub(%r{</p>\s*}i, "\n\n").gsub(/<br\s*\/?>/i, "\n")
    ActionView::Base.full_sanitizer.sanitize(text).to_s.gsub(/\n{3,}/, "\n\n").strip
  end

  # Plain text a manager wrote, as safe HTML paragraphs.
  def self.paragraphs(text)
    h = ActionController::Base.helpers
    h.safe_join(text.to_s.strip.split(/\n{2,}/).map { |paragraph|
      h.content_tag(:p, h.safe_join(paragraph.strip.split("\n"), h.tag.br))
    })
  end

  private

  # An email with the order's tickets in it: the words, then one QR code per
  # ticket, attached inline so the door can scan straight from the email.
  def deliver_tickets(order, subject:, body_html:)
    @order = order
    @listing = order.ticket_listing
    @tickets = order.tickets.where(status: Ticket::SOLD_STATUSES).includes(:ticket_tier).order(:id).to_a
    @items = order.ticket_order_items.sold.order(:id).to_a
    @intro_html = body_html

    @tickets.each do |ticket|
      png = RQRCode::QRCode.new(tickets_ticket_url(code: ticket.code)).as_png(size: 360, border_modules: 2)
      attachments.inline["ticket-#{ticket.id}.png"] = png.to_s
    end
    deliver_from_theater(subject, template_name: "confirmation")
  end

  # A template's words. The subject is plain text; in the body every value
  # is escaped, since names and titles come from people.
  def render_words(key, variables)
    { subject: ContentTemplateService.render_subject(key, variables),
      body_html: ContentTemplateService.render_body(key, variables.transform_values { |value| ERB::Util.html_escape(value.to_s) }) }
  end

  def deliver_from_theater(subject, **options)
    organization = @order.organization
    mail(to: @order.buyer_email, subject: subject,
         from: email_address_with_name("info@cocoscout.com", "#{organization.name} via CocoScout"),
         reply_to: TicketingProfile.for(organization).support_email.presence, **options)
  end
end
