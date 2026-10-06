# frozen_string_literal: true

module TicketingHelper
  # Where a show's sales stand, in words and a badge color. Sold out wins over
  # "on sale"; a scheduled opening says when.
  def ticket_listing_status_badge(listing, inventory = listing.inventory, at: Time.current)
    case listing.status
    when "draft" then [ "Draft", "bg-gray-100 text-gray-600" ]
    when "paused" then [ "Paused", "bg-amber-100 text-amber-700" ]
    when "closed" then [ "Sales closed", "bg-gray-100 text-gray-600" ]
    when "canceled" then [ "Canceled", "bg-red-100 text-red-700" ]
    else
      if inventory.sold_out? then [ "Sold out", "bg-pink-100 text-pink-700" ]
      elsif listing.on_sale_at&.>(at) then [ "Opens #{listing.on_sale_at.strftime('%b %-d')}", "bg-blue-100 text-blue-700" ]
      elsif listing.off_sale_at && listing.off_sale_at <= at then [ "Sales closed", "bg-gray-100 text-gray-600" ]
      else [ "On sale", "bg-green-100 text-green-700" ]
      end
    end
  end

  # The image a show's ticket page leads with (Show#ticket_page_image), as a
  # display-sized image that keeps its own shape (never cropped). Returns
  # [image, page_image], or nil when the show and production have no image.
  def ticket_page_image(listing)
    page_image = listing.show.ticket_page_image
    return nil unless page_image

    image = begin
      page_image.attachment.variant(page_image.wide? ? :display : :large)
    rescue ActiveStorage::InvariableError, ActiveStorage::FileNotFoundError
      page_image.attachment
    end
    [ image, page_image ]
  end

  # Which image that is, in words a manager reads.
  def ticket_page_image_source(page_image)
    return "No image yet" unless page_image

    whose = page_image.own? ? "This show's" : "The production's"
    "#{whose} #{page_image.wide? ? 'wide image' : 'poster'}"
  end

  # "Rising Stars'" / "Improv Night's".
  def possessive(name)
    name.to_s.end_with?("s") ? "#{name}'" : "#{name}'s"
  end

  # A production's public ticket page, by its key: /tickets/<org>/<production-key>.
  def ticket_production_path(profile, production, **options)
    tickets_event_path(org: profile.slug, event: production.public_key, **options)
  end

  def ticket_production_url(profile, production, **options)
    tickets_event_url(org: profile.slug, event: production.public_key, **options)
  end

  # A date as its pages name it: "Sat, Oct 5 · 7:30 PM".
  def ticket_listing_date_label(listing)
    listing.show.date_and_time.strftime("%a, %b %-d · %-l:%M %p")
  end

  # The trail above every page about one date: Ticketing / Productions / its
  # production / the date (left off on the date's own page).
  def ticket_listing_breadcrumbs(listing, include_date: true)
    crumbs = [ [ "Ticketing", manage_ticketing_path ], [ "Productions", manage_ticket_listings_path ],
               [ listing.production.name, manage_production_ticketing_path(listing.production) ] ]
    crumbs << [ ticket_listing_date_label(listing), manage_ticket_listing_path(listing) ] if include_date
    crumbs
  end

  # The choices for when a ticket page says "Only N left": the usual few,
  # the current value if it's something else, and not at all.
  def low_stock_choices(current = nil)
    counts = ([ 3, 5, 10, 15, 20 ] + [ current.to_i ]).select(&:positive?).uniq.sort
    counts.map { |n| [ "When #{n} or fewer are left#{' (the usual)' if n == TicketListing::LOW_STOCK_DEFAULT}", n ] } + [ [ "Never", 0 ] ]
  end

  # "$20.00" / "Free"
  def ticket_price(cents)
    cents.to_i.zero? ? "Free" : number_to_currency(cents / 100.0)
  end

  PriceBreakdown = Data.define(:rows, :total_cents)

  # The checkout summary's lines for a ticket order: tickets by type,
  # products, then the discount, fees and added tax (muted). Rendered by
  # shared/checkout/_summary.
  def ticket_summary_lines(order)
    tickets = order.tickets.to_a
    items = order.ticket_order_items.to_a
    lines = tickets.group_by { |t| t.bundle_tier || t.ticket_tier }.map do |tier, rows|
      count = rows.size / [ tier.admits.to_i, 1 ].max
      [ "#{count} × #{tier.name}", rows.sum(&:price_cents), false ]
    end
    items.each { |item| lines << [ "#{item.quantity} × #{item.name}", item.price_cents, false ] }
    if order.discount_cents.positive?
      lines << [ "Discount#{" (#{order.ticket_discount_code.code})" if order.ticket_discount_code}", -order.discount_cents, true ]
    end
    lines << [ "Fees", order.buyer_fee_cents, true ] if order.buyer_fee_cents.positive?
    TaxLine.where(taxable: tickets + items, included: false).group(:name, :rate_bps).sum(:tax_cents).each do |(name, rate_bps), cents|
      lines << [ "#{name} #{format('%g', rate_bps / 100.0)}%", cents, true ] if cents.positive?
    end
    lines
  end

  # What one ticket of a tier is made of, for the panel under its price on
  # the show's page: the ticket, the fees, the tax, adding up to the all-in
  # price shown (TicketPricing's own math). One row means there's nothing to
  # break down.
  def ticket_price_breakdown(listing, tier)
    # A type admitting several people is taxed and priced ticket by ticket.
    taxes = tier.seat_prices.map { |cents| TaxCalculator.for_ticket(listing, tier.base_tier, cents) }
    taxed = taxes.flat_map(&:lines).reject(&:exempt)
    label = ticket_tax_label(taxed, rate: false)
    included = taxed.select(&:included).sum(&:tax_cents)
    added = taxes.sum(&:added_cents)
    total = TicketPricing.all_in_price_cents(listing, tier)
    fees = total - tier.price_cents - added

    # Tax inside the price is shown apart too, so the rows always add up.
    rows = [ [ tier.bundle? ? tier.name : "Ticket", tier.price_cents - included ] ]
    rows << [ "Fees", fees ] if fees.positive?
    rows << [ label, included + added ] if (included + added).positive?
    PriceBreakdown.new(rows: rows, total_cents: total)
  end

  # "Sales tax 10.25%" ("Sales tax" where space is tight), or just "Tax"
  # when several apply.
  def ticket_tax_label(lines, rate: true)
    return "Tax" unless lines.map { |line| [ line.name, line.rate_bps ] }.uniq.one?

    rate ? "#{lines.first.name} #{format('%g', lines.first.rate_bps / 100.0)}%" : lines.first.name
  end

  # The short address a date is shared at: cocoscout.com/t/K7M2P/oct-10.
  def ticket_public_path_text(listing)
    "cocoscout.com#{ShortLink.canonical_for!(listing.production).short_path(ShortLink.date_suffix(listing.show))}"
  end

  # How a show's sales read to a buyer: nil when it's simply on sale.
  def public_listing_note(listing, inventory = listing.inventory, at: Time.current)
    return "Sold out" if inventory.sold_out?
    return "Not on sale right now" if listing.status == "paused"
    return "Tickets at the door" if listing.status == "closed" || (listing.off_sale_at && listing.off_sale_at <= at)
    return "On sale #{listing.on_sale_at.strftime('%b %-d')}" if listing.on_sale_at&.>(at)

    listing.low_stock_note(inventory.remaining)
  end

  # The lowest all-in price a buyer can see for a show, for "From $21.42".
  def listing_from_price_cents(listing)
    listing.ticket_tiers.select { |tier| tier.archived_at.nil? && !tier.hidden? }
           .map { |tier| TicketPricing.all_in_price_cents(listing, tier) }.min
  end

  # The QR a ticket carries: its own /tickets/v page, which the door scanner reads
  # and a phone camera opens.
  def ticket_qr_svg(ticket)
    RQRCode::QRCode.new(tickets_ticket_url(code: ticket.code))
                   .as_svg(module_size: 4, standalone: true, use_path: true, viewbox: true, svg_attributes: { class: "w-full h-auto" })
                   .html_safe
  end

  # A QR code for any link, as inline SVG: the door's "scan to pay" code.
  def link_qr_svg(url)
    RQRCode::QRCode.new(url).as_svg(module_size: 6, standalone: true, use_path: true, viewbox: true,
                                    svg_attributes: { class: "w-full h-auto" }).html_safe
  end

  # Stripe's browser-side key, read like the secret key in the Stripe
  # initializer: the environment first, then credentials.
  def stripe_publishable_key
    ENV["STRIPE_PUBLISHABLE_KEY"].presence || Rails.application.credentials.dig(:stripe, :publishable_key)
  end
end
