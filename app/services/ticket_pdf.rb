# frozen_string_literal: true

require "prawn"

# A buyer's tickets as a PDF (bytes): one letter page per ticket, each with
# the show, when and where, who it's for, its type, the order, "Ticket N of M"
# and its QR code (the same /tickets/v/<code> link the email's QR opens).
# Attached to the confirmation email when the organization turns it on
# (ticketing_profiles.attach_pdf_tickets), and downloadable from the order
# page either way. Groups' bulk PDFs and the door's ticket printer reuse this
# layout. Pure renderer, never stored.
class TicketPdf
  include PdfHelpers

  INK = "111827"
  BODY = "374151"
  GRAY = "6b7280"
  FAINT = "9ca3af"
  LINE = "d1d5db"
  PAD = 21     # inside the ticket's border
  STUB = 172   # the QR column on the right
  QR = 140     # about 2 inches: easy for a door scanner, printed or on a phone

  # One order, or several (a pass's shows, in one purchase): each order's
  # tickets in turn, counted within their order.
  def initialize(orders)
    @orders = Array(orders)
  end

  def self.filename(order)
    "tickets-#{order.code}.pdf"
  end

  def tickets?
    @orders.any? { |order| tickets_for(order).any? }
  end

  def render
    Prawn::Fonts::AFM.hide_m17n_warning = true
    first = @orders.first.ticket_listing
    pdf = Prawn::Document.new(page_size: "LETTER", margin: 42, info: { Title: winansi("Tickets: #{first.display_title}") })
    started = false
    @orders.each do |order|
      tickets = tickets_for(order)
      tickets.each_with_index do |ticket, index|
        pdf.start_new_page if started
        started = true
        page(pdf, order, ticket, "Ticket #{index + 1} of #{tickets.size}")
      end
    end
    pdf.render
  end

  private

  def tickets_for(order)
    @tickets ||= {}
    @tickets[order.id] ||= order.tickets.where(status: Ticket::SOLD_STATUSES).includes(:ticket_tier, :ticket_pass, :bundle_tier).order(:id).to_a
  end

  def page(pdf, order, ticket, count_words)
    listing = order.ticket_listing
    top = pdf.cursor
    width = pdf.bounds.width
    details = pdf.bounding_box([ PAD, top - PAD ], width: width - STUB - (PAD * 2)) do
      details(pdf, order, listing, ticket, count_words)
    end
    height = [ details.height + (PAD * 2), QR + 72 ].max

    stub(pdf, ticket, x: width - STUB, top: top, height: height)
    pdf.stroke_color INK
    pdf.line_width 1.5
    pdf.stroke_rounded_rectangle [ 0, top ], width, height, 12
    pdf.line_width 1
    pdf.stroke_color "000000"

    pdf.move_cursor_to top - height - 24
    good_to_know(pdf, order, listing)
    footer(pdf)
  end

  def details(pdf, order, listing, ticket, count_words)
    show = listing.show
    pdf.text winansi(listing.organization.name.upcase), size: 9.5, color: GRAY, character_spacing: 0.6
    pdf.move_down 8
    pdf.text winansi(listing.display_title), size: 26, style: :bold, color: INK, leading: 2
    pdf.move_down 8
    pdf.text winansi(show.date_and_time.strftime("%A, %B %-d, %Y · %-l:%M %p")), size: 13.5, style: :bold, color: INK
    place = place_words(show)
    if place.present?
      pdf.move_down 5
      pdf.text winansi(place), size: 10.5, color: BODY
    end
    seat_block(pdf, ticket)
    pdf.move_down 12
    holder = ticket.holder_name.presence || order.buyer_name
    line = [ holder, ticket.type_label, "Order #{order.code}", count_words ].compact_blank.join(" · ")
    pdf.text winansi(line), size: 10, color: BODY
  end

  # The room, then the venue, then its address; online shows say so.
  def place_words(show)
    return "Online" if show.is_online

    location = show.location
    address = [ location&.address1, [ location&.city, location&.state ].compact_blank.join(", ") ].compact_blank.join(", ")
    [ show.location_space&.name, location&.name, address ].compact_blank.uniq.join(" · ")
  end

  # A ticket's seat, as { section:, row:, seat: }. Reserved seating (the
  # advanced-ticketing plan's step 4) fills this in; until then no ticket has
  # a seat and seat_block draws nothing.
  def seat_for(_ticket)
    nil
  end

  # Section, row and seat, each in its own box, as the door reads them.
  def seat_block(pdf, ticket)
    seat = seat_for(ticket)
    return if seat.blank?

    boxes = [ [ "SECTION", seat[:section] ], [ "ROW", seat[:row] ], [ "SEAT", seat[:seat] ] ].select { |_, value| value.present? }
    return if boxes.empty?

    pdf.move_down 12
    top = pdf.cursor
    x = 0
    boxes.each do |label, value|
      value = winansi(value.to_s)
      box_width = [ pdf.width_of(value, size: 15, style: :bold) + 24, 52 ].max
      pdf.stroke_color LINE
      pdf.stroke_rounded_rectangle [ x, top ], box_width, 40, 7
      pdf.stroke_color "000000"
      in_color(pdf, GRAY) { pdf.text_box label, at: [ x, top - 6 ], width: box_width, size: 8, align: :center }
      in_color(pdf, INK) { pdf.text_box value, at: [ x, top - 18 ], width: box_width, size: 15, style: :bold, align: :center }
      x += box_width + 8
    end
    pdf.move_cursor_to top - 40
  end

  # The tear-off side: the QR, a dashed line between it and the details.
  def stub(pdf, ticket, x:, top:, height:)
    pdf.stroke_color FAINT
    pdf.line_width 1.5
    pdf.dash(4, space: 4)
    pdf.stroke_vertical_line top, top - height, at: x
    pdf.undash
    pdf.line_width 1
    pdf.stroke_color "000000"

    qr_top = top - ((height - QR - 30) / 2.0)
    pdf.image qr_png(ticket), at: [ x + ((STUB - QR) / 2.0), qr_top ], width: QR
    in_color(pdf, GRAY) do
      pdf.text_box "Scan at the door.\nOne code, one person.", at: [ x + 8, qr_top - QR - 6 ], width: STUB - 16, size: 8, align: :center
    end
  end

  def qr_png(ticket)
    url = Rails.application.routes.url_helpers.tickets_ticket_url(code: ticket.code, **TicketOrderMailer.url_options)
    StringIO.new(RQRCode::QRCode.new(url).as_png(size: 600, border_modules: 2).to_s)
  end

  # Under the ticket: how to get there, and what to know before coming.
  def good_to_know(pdf, order, listing)
    where = TicketOrderMailer.when_where(listing)
    getting_here = [ where[:venue], where[:address] ].compact_blank.uniq
    know = [ where[:ages], where[:door_note], where[:notes], order.refund_policy_words ].compact_blank
    columns = [ [ "Getting here", getting_here ], [ "Good to know", know ] ].reject { |_, lines| lines.empty? }
    return if columns.empty?

    top = pdf.cursor
    gap = 18
    column_width = (pdf.bounds.width - gap) / 2.0
    bottoms = columns.each_with_index.map do |(title, lines), index|
      pdf.bounding_box([ index * (column_width + gap), top ], width: column_width) do
        pdf.text title, size: 10, style: :bold, color: INK
        pdf.move_down 3
        lines.each { |line| pdf.text winansi(line), size: 10, color: BODY, leading: 2 }
      end
      pdf.cursor
    end
    pdf.move_cursor_to bottoms.min
  end

  def footer(pdf)
    in_color(pdf, FAINT) { pdf.text_box "Tickets by CocoScout", at: [ 0, 10 ], width: pdf.bounds.width, size: 8, align: :center }
  end

  # text_box takes no color of its own.
  def in_color(pdf, color)
    pdf.fill_color color
    yield
  ensure
    pdf.fill_color "000000"
  end
end
