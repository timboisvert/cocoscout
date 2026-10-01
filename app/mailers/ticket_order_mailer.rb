# frozen_string_literal: true

# A buyer's tickets by email. The words come from the
# ticket_order_confirmation content template; under them sits one QR code per
# ticket, attached inline, so the door can scan straight from the email.
class TicketOrderMailer < ApplicationMailer
  def confirmation(order)
    @order = order
    @listing = order.ticket_listing
    @tickets = order.tickets.where(status: Ticket::SOLD_STATUSES).includes(:ticket_tier).order(:id).to_a
    organization = @listing.organization
    profile = TicketingProfile.for(organization)
    show = @listing.show

    rendered = ContentTemplateService.render("ticket_order_confirmation", {
      first_name: order.buyer_name.to_s.split.first.presence || "there",
      organization_name: organization.name,
      show_title: @listing.display_title,
      show_date: show.date_and_time.strftime("%A, %B %-d"),
      show_time: show.date_and_time.strftime("%-l:%M %p"),
      venue: [ show.location&.name, show.location_space&.name ].compact.uniq.join(", "),
      ticket_count: ActionController::Base.helpers.pluralize(@tickets.size, "ticket"),
      ticket_count_verb: @tickets.size == 1 ? "is" : "are",
      order_code: order.code,
      order_url: tickets_order_url(token: order.token)
    })
    @intro_html = rendered[:body]

    @tickets.each do |ticket|
      png = RQRCode::QRCode.new(tickets_ticket_url(code: ticket.code)).as_png(size: 360, border_modules: 2)
      attachments.inline["ticket-#{ticket.id}.png"] = png.to_s
    end

    mail(to: order.buyer_email, subject: rendered[:subject],
         from: email_address_with_name("info@cocoscout.com", "#{organization.name} via CocoScout"),
         reply_to: profile.support_email.presence)
  end

  # Money back, from the ticket_order_refunded template.
  def refunded(refund)
    @order = refund.ticket_order
    rendered = ContentTemplateService.render("ticket_order_refunded", self.class.variables_for(@order, refund))
    @body_html = rendered[:body]
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
      order_url: Rails.application.routes.url_helpers.tickets_order_url(
        token: order.token, **(Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 })
      )
    }
  end

  # Plain text a manager wrote, as safe HTML paragraphs.
  def self.paragraphs(text)
    h = ActionController::Base.helpers
    h.safe_join(text.to_s.strip.split(/\n{2,}/).map { |paragraph|
      h.content_tag(:p, h.safe_join(paragraph.strip.split("\n"), h.tag.br))
    })
  end

  private

  def deliver_from_theater(subject)
    organization = @order.organization
    mail(to: @order.buyer_email, subject: subject,
         from: email_address_with_name("info@cocoscout.com", "#{organization.name} via CocoScout"),
         reply_to: TicketingProfile.for(organization).support_email.presence)
  end
end
