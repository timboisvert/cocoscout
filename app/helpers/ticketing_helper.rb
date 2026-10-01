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
end
