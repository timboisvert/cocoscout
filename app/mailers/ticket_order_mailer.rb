# frozen_string_literal: true

# A buyer's emails about their order: their tickets (the confirmation, the
# reminder before the show, a show that moved, tickets moved to another
# date), refunds, and a canceled show. The words come
# from content templates; under the words of an email with tickets sits one
# QR code per ticket.
class TicketOrderMailer < ApplicationMailer
  helper TicketingHelper

  # A buyer's email is the theater's: its name leads the frame and the footer
  # says "Ticketing by CocoScout" (layouts/mailer, @storefront_organization), so
  # CocoScout's cat isn't attached at all.
  skip_before_action :attach_logo

  # Their tickets, with a receipt: what they paid, line by line.
  def confirmation(order)
    @receipt = order.total_cents.positive?
    # Deals on another show they can still add (TicketCheckout.deals_after).
    @deals = TicketCheckout.deals_after(order)
    pdf = pdf_tickets(order)
    attachments[TicketPdf.filename(order)] = { mime_type: "application/pdf", content: pdf } if pdf
    deliver_tickets(order, **render_words("ticket_order_confirmation", self.class.ticket_variables(order).merge(pdf_attached: pdf ? "yes" : "")))
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
  # the ticket_order_moved template). Moved to another ticket type on the
  # same date, it's the ticket_order_retyped template: what they were, what
  # they are now.
  def moved(exchange)
    order = exchange.to_order
    refund = exchange.ticket_refund
    refunded = refund&.status == "succeeded" ? ActiveSupport::NumberHelper.number_to_currency(refund.amount_cents / 100.0) : ""
    if order.ticket_listing_id == exchange.from_order.ticket_listing_id
      type_names = ->(tickets) { tickets.map { |t| (t.bundle_tier || t.ticket_tier).name }.uniq.to_sentence }
      return deliver_tickets(order, **render_words("ticket_order_retyped", self.class.ticket_variables(order).merge(
        was_type: type_names.call(Ticket.where(id: exchange.ticket_ids).includes(:ticket_tier, :bundle_tier)),
        new_type: type_names.call(order.tickets.includes(:ticket_tier, :bundle_tier)),
        refund_amount: refunded
      )))
    end

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
    pdf = pdf_tickets(@orders)
    attachments["tickets.pdf"] = { mime_type: "application/pdf", content: pdf } if pdf
    shows = @orders.map { |order| "#{order.ticket_listing.display_title} (#{order.ticket_listing.show.date_and_time.strftime('%a, %b %-d')})" }
    words = render_words("ticket_purchase_confirmation", {
      first_name: @order.buyer_name.to_s.split.first.presence || "there",
      organization_name: @order.organization.name,
      what: pass&.name || shows.to_sentence,
      show_count: ActionController::Base.helpers.pluralize(@orders.size, "show"),
      show_list: shows.to_sentence,
      pass_name: pass&.name.to_s,
      refund_policy: purchase_refund_words(@orders),
      pdf_attached: pdf ? "yes" : ""
    })
    @intro_html = words[:body_html]
    @sections = @orders.map do |order|
      tickets = order.tickets.where(status: Ticket::SOLD_STATUSES).includes(:ticket_tier, :ticket_pass, :bundle_tier).order(:id).to_a
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
    @storefront_organization = @organization
    words = render_words("ticket_pass_bought", self.class.pass_variables(holding))
    @intro_html = words[:body_html]
    mail(to: holding.holder_email, subject: words[:subject],
         from: email_address_with_name("info@cocoscout.com", "#{@organization.name} via CocoScout"),
         reply_to: TicketingProfile.for(@organization).support_email.presence)
  end

  # A credit pass ending with credits left (TicketPassEndingJob).
  def pass_ending(holding)
    @organization = holding.organization
    @storefront_organization = @organization
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
  # who can come, the door note. Rendered as its own block under an email's
  # words (shared/mailer/_when_where), so the confirmation, the reminder and
  # every other email with tickets says the same.
  def self.when_where(listing)
    Ticketing::WhenWhere.for(listing.show, door_note: listing.effective_door_note, ages: listing.age_words(label: true),
                             notes: listing.effective_accessibility_note)
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

  # Tickets that cost nothing (a comp) canceled by the theater: no money to
  # give back, but the guest hears they no longer work, from the
  # ticket_order_canceled template.
  def tickets_canceled(refund)
    @order = refund.ticket_order
    rendered = render_words("ticket_order_canceled", self.class.variables_for(@order, refund))
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
      order_url: routes.tickets_order_url(token: order.token, **url_options),
      refund_message: refund&.buyer_message.to_s.strip,
      refund_where: refund_where_words(refund)
    }
  end

  # Where a refund goes back to: the card, the gift certificate that paid,
  # or both. A preview (no refund yet) says the card.
  def self.refund_where_words(refund)
    gift = refund&.gift_certificate_cents.to_i
    card = refund ? refund.amount_cents - gift : 1
    money = ->(cents) { ActiveSupport::NumberHelper.number_to_currency(cents / 100.0) }
    if gift.positive? && card.positive?
      "#{money.call(gift)} goes back onto your gift certificate, ready for your next order, and #{money.call(card)} to the card you paid with, which usually shows up within 5 to 10 business days."
    elsif gift.positive?
      "It goes back onto your gift certificate, ready for your next order."
    else
      "It goes back to the card you paid with and usually shows up within 5 to 10 business days."
    end
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

  # The tickets as one PDF (TicketPdf), when the organization attaches them
  # (Ticketing → Settings → Box office). These emails go out only from
  # TicketOrderConfirmationJob and TicketPurchaseConfirmationJob, so the PDF
  # is drawn in a job, never on a request.
  def pdf_tickets(orders)
    orders = Array(orders)
    return nil unless TicketingProfile.for(orders.first.organization).attach_pdf_tickets?

    pdf = TicketPdf.new(orders)
    pdf.render if pdf.tickets?
  end

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
    @storefront_organization = organization
    mail(to: @order.buyer_email, subject: subject,
         from: email_address_with_name("info@cocoscout.com", "#{organization.name} via CocoScout"),
         reply_to: TicketingProfile.for(organization).support_email.presence, **options)
  end
end
