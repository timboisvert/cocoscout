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

  # "$20.00" / "Free"
  def ticket_price(cents)
    cents.to_i.zero? ? "Free" : number_to_currency(cents / 100.0)
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
