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
end
