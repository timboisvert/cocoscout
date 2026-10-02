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

  # "$20.00" / "Free"
  def ticket_price(cents)
    cents.to_i.zero? ? "Free" : number_to_currency(cents / 100.0)
  end

  PriceBreakdown = Data.define(:rows, :total_cents)

  # What one ticket of a tier is made of, for the panel under its price on
  # the show's page: the ticket, the fees, the tax, adding up to the all-in
  # price shown (TicketPricing's own math). One row means there's nothing to
  # break down.
  def ticket_price_breakdown(listing, tier)
    tax = TaxCalculator.for_ticket(listing, tier, tier.price_cents)
    taxed = tax.lines.reject(&:exempt)
    label = ticket_tax_label(taxed, rate: false)
    included = taxed.select(&:included).sum(&:tax_cents)
    added = tax.added_cents
    total = TicketPricing.all_in_price_cents(listing, tier)
    fees = total - tier.price_cents - added

    # Tax inside the price is shown apart too, so the rows always add up.
    rows = [ [ "Ticket", tier.price_cents - included ] ]
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

  def ticket_public_path_text(listing)
    "cocoscout.com/t/#{listing.organization.ticketing_profile&.slug || TicketingProfile.for(listing.organization).slug}/#{listing.slug}"
  end

  # How a show's sales read to a buyer: nil when it's simply on sale.
  def public_listing_note(listing, inventory = listing.inventory, at: Time.current)
    return "Sold out" if inventory.sold_out?
    return "Not on sale right now" if listing.status == "paused"
    return "Tickets at the door" if listing.status == "closed" || (listing.off_sale_at && listing.off_sale_at <= at)
    return "On sale #{listing.on_sale_at.strftime('%b %-d')}" if listing.on_sale_at&.>(at)

    left = inventory.remaining
    "Only #{left} left" if left && left <= 10
  end

  # The lowest all-in price a buyer can see for a show, for "From $21.42".
  def listing_from_price_cents(listing)
    listing.ticket_tiers.select { |tier| tier.archived_at.nil? && !tier.hidden? }
           .map { |tier| TicketPricing.all_in_price_cents(listing, tier) }.min
  end

  # The QR a ticket carries: its own /t/v page, which the door scanner reads
  # and a phone camera opens.
  def ticket_qr_svg(ticket)
    RQRCode::QRCode.new(tickets_ticket_url(code: ticket.code))
                   .as_svg(module_size: 4, standalone: true, use_path: true, viewbox: true, svg_attributes: { class: "w-full h-auto" })
                   .html_safe
  end

  # Stripe's browser-side key, read like the secret key in the Stripe
  # initializer: the environment first, then credentials.
  def stripe_publishable_key
    ENV["STRIPE_PUBLISHABLE_KEY"].presence || Rails.application.credentials.dig(:stripe, :publishable_key)
  end
end
