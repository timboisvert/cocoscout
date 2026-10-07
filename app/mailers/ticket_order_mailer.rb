# frozen_string_literal: true

# A buyer's emails about their order: their tickets (the confirmation, the
# reminder before the show, a show that moved, tickets moved to another
# date), refunds, and a canceled show. The words come
# from content templates; under the words of an email with tickets sits one
# QR code per ticket.
class TicketOrderMailer < ApplicationMailer
  helper TicketingHelper

  # Their tickets, with a receipt: what they paid, line by line.
  def confirmation(order)
    @receipt = order.total_cents.positive?
    # Deals on another show they can still add (TicketCheckout.deals_after).
    @deals = TicketCheckout.deals_after(order)
    deliver_tickets(order, **render_words("ticket_order_confirmation", self.class.ticket_variables(order)))
  end

  # A few days before the show (as many as the theater chose): the time,
  # the place and the tickets again, from the ticket_event_reminder template.
  # Mail apps' own unsubscribe button turns reminders off for this order.
  def reminder(order)
    show = order.ticket_listing.show
    @stop_url = tickets_order_reminders_url(token: order.token)
    headers["List-Unsubscribe"] = "<#{tickets_order_stop_reminders_url(token: order.token)}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
    deliver_tickets(order, **render_words("ticket_event_reminder", self.class.ticket_variables(order).merge(
      when: self.class.when_words(show.date_and_time)
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

  # Several shows bought at once (a pass): one email, each show with its
  # when and where and its QR codes, and one receipt for the whole purchase.
  def purchase_confirmation(purchase)
    @purchase = purchase
    @orders = purchase.ticket_orders.select(&:paid?)
    @order = @orders.first
    pass = @order.tickets.first&.ticket_pass
    shows = @orders.map { |order| "#{order.ticket_listing.display_title} (#{order.ticket_listing.show.date_and_time.strftime('%a, %b %-d')})" }
    words = render_words("ticket_purchase_confirmation", {
      first_name: @order.buyer_name.to_s.split.first.presence || "there",
      organization_name: @order.organization.name,
      what: pass&.name || shows.to_sentence,
      show_count: ActionController::Base.helpers.pluralize(@orders.size, "show"),
      show_list: shows.to_sentence,
      pass_name: pass&.name.to_s,
      refund_policy: purchase_refund_words(@orders)
    })
    @intro_html = words[:body_html]
    @sections = @orders.map do |order|
      tickets = order.tickets.where(status: Ticket::SOLD_STATUSES).includes(:ticket_tier, :ticket_pass).order(:id).to_a
      tickets.each do |ticket|
        png = RQRCode::QRCode.new(tickets_ticket_url(code: ticket.code)).as_png(size: 360, border_modules: 2)
        attachments.inline["ticket-#{ticket.id}.png"] = png.to_s
      end
      { order: order, when_where: self.class.when_where(order.ticket_listing), tickets: tickets }
    end
    deliver_from_theater(words[:subject])
  end

  # Credit passes bought (TicketPassCredits): each one's page, where its
  # credits are used, and a receipt.
  def passes(purchase)
    @purchase = purchase
    @holdings = purchase.ticket_pass_holdings.select { |holding| holding.status == "active" }
    holding = @holdings.first
    @organization = holding.organization
    words = render_words("ticket_pass_bought", self.class.pass_variables(holding))
    @intro_html = words[:body_html]
    mail(to: holding.holder_email, subject: words[:subject],
         from: email_address_with_name("info@cocoscout.com", "#{@organization.name} via CocoScout"),
         reply_to: TicketingProfile.for(@organization).support_email.presence)
  end

  # A credit pass ending with credits left (TicketPassEndingJob).
  def pass_ending(holding)
    @organization = holding.organization
    variables = self.class.pass_variables(holding).merge(
      credits_left: ActionController::Base.helpers.pluralize(holding.credits_left, "credit"),
      pass_url: tickets_pass_holding_url(token: holding.token)
    )
    words = render_words("ticket_pass_ending", variables)
    mail(to: holding.holder_email, subject: words[:subject],
         from: email_address_with_name("info@cocoscout.com", "#{@organization.name} via CocoScout"),
         reply_to: TicketingProfile.for(@organization).support_email.presence) do |format|
      format.html { render html: words[:body_html].html_safe, layout: "mailer" }
    end
  end

  def self.pass_variables(holding)
    pass = holding.ticket_pass
    {
      first_name: holding.holder_name.to_s.split.first.presence || "there",
      organization_name: holding.organization.name,
      pass_name: pass.name,
      credits_words: pass.kind == "season" ? "a seat at up to #{holding.credits} shows" : ActionController::Base.helpers.pluralize(holding.credits, "credit"),
      covers: pass.coverages.includes(:production).map { |coverage| coverage.production.name }.to_sentence,
      ends_on: holding.ends_on.strftime("%B %-d, %Y")
    }
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
      order_url: routes.tickets_order_url(token: order.token, **url_options),
      refund_policy: order.refund_policy_words.to_s
    }
  end

  # Everything a buyer needs to turn up: the time, the place, directions,
  # the door note. Rendered as its own block under an email's words
  # (shared/mailer/_when_where).
  def self.when_where(listing)
    Ticketing::WhenWhere.for(listing.show, door_note: listing.effective_door_note,
                             notes: [ listing.effective_age_note, listing.effective_accessibility_note ].compact_blank.join(" · "))
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

  # One policy for the whole purchase, or each show's when they differ.
  def purchase_refund_words(orders)
    words = orders.to_h { |order| [ order.ticket_listing.display_title, order.refund_policy_words ] }.compact
    return words.values.first.to_s if words.values.uniq.size <= 1

    words.map { |title, text| "#{title}: #{text}" }.join(" ")
  end

  # An email with the order's tickets in it: the words, the show's when and
  # where, then one QR code per ticket, attached inline so the door can scan
  # straight from the email, then any products and the order link.
  def deliver_tickets(order, subject:, body_html:)
    @order = order
    @listing = order.ticket_listing
    @tickets = order.tickets.where(status: Ticket::SOLD_STATUSES).includes(:ticket_tier).order(:id).to_a
    @items = order.ticket_order_items.sold.order(:id).to_a
    @intro_html = body_html
    @when_where = self.class.when_where(@listing)

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
