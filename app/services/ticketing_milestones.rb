# frozen_string_literal: true

# After seats are taken (a sale, comps, the door): tell the theater when a
# show or one of its ticket types sells out, and when a show is almost out:
# from the same number of seats left the ticket page says "Only N left"
# (Tim, 2026-10-05), and not at all when the theater turned that off (0).
# Each fires once per show (or ticket type).
class TicketingMilestones
  def self.check!(listing)
    inventory = listing.inventory
    organization = listing.organization

    if inventory.sold_out?
      TicketingNotifier.notify(organization, :sold_out, variables: TicketingNotificationContent.milestone(listing),
                                                        about: listing, once: true)
    elsif (left = inventory.remaining) && inventory.capacity.to_i.positive? && (threshold = listing.effective_low_stock_threshold).positive? && left <= threshold
      TicketingNotifier.notify(organization, :almost_sold_out, variables: TicketingNotificationContent.milestone(listing),
                                                               about: listing, once: true)
    end

    listing.ticket_tiers.active.where.not(quantity: nil).find_each do |tier|
      next unless inventory.remaining(tier: tier).to_i.zero?
      next if inventory.sold_out? # the whole show's notice says it

      TicketingNotifier.notify(organization, :sold_out, variables: TicketingNotificationContent.milestone(listing, what: "#{tier.name} tickets"),
                                                        about: tier, once: true)
    end
  end
end
