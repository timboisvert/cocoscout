# frozen_string_literal: true

module Ticketing
  # Buying, renewing and running memberships (advanced ticketing §2b). A
  # purchase is a TicketPurchase with no show (as a credit pass is); paid,
  # the membership goes active, its dues post to Membership dues, our 50¢
  # and the processing to Ticketing fees (D4: every sale through our checkout
  # costs the organization fifty cents), and the member gets their card by
  # email. No auto-renew: reminders at 30 and 7 days, and a renew link.
  class Memberships
    class Error < StandardError; end

    BUY_HOLD = 30.minutes

    def self.start!(level:, renewed_from: nil, email: nil, name: nil)
      raise Error, "This membership isn't on sale right now." unless level.status == "on_sale"

      starts_on = renewed_from && renewed_from.ends_on >= Date.current ? renewed_from.ends_on + 1 : Date.current
      ActiveRecord::Base.transaction do
        purchase = TicketPurchase.create!(organization: level.organization, channel: "online", expires_at: BUY_HOLD.from_now)
        purchase.ticket_memberships.create!(organization: level.organization, level: level, renewed_from: renewed_from,
                                            holder_name: name.presence || renewed_from&.holder_name, holder_email: email.presence || renewed_from&.holder_email,
                                            starts_on: starts_on, ends_on: starts_on + level.period_months.months - 1.day, price_cents: level.price_cents)
        purchase.price!
      end
    end

    def self.settle!(membership, paid_at:)
      membership.with_lock do
        next unless membership.status == "pending"

        membership.update!(status: "active", paid_at: paid_at)
        membership.renewed_from&.update!(status: "renewed") if membership.renewed_from&.status.in?(%w[active expired])
        organization = membership.organization
        if membership.total_cents.positive?
          OrgCashEntry.post!(organization: organization, entry_type: "membership_sale", amount_cents: membership.org_net_cents, source: membership,
                             description: "Membership #{membership.level.name}", occurred_at: paid_at)
          LedgerPosting.post!(organization: organization, source: membership, kind: "sale", entry_date: paid_at.to_date, cash_date: paid_at.to_date,
                              memo: "Membership #{membership.level.name}", lines: [
                                { account: :cocoscout_balance, amount_cents: membership.org_net_cents },
                                { account: :ticketing_fees, amount_cents: membership.platform_fee_cents + membership.processing_cents },
                                { account: :fees_paid_by_buyers, amount_cents: -membership.buyer_fee_cents },
                                { account: :membership_dues, amount_cents: -membership.price_cents }
                              ])
        end
        if membership.holder_email.present?
          membership.update!(follower: Follower.for!(organization, membership.holder_email, name: membership.holder_name, consented: false))
          TicketMembershipMailer.welcome(membership).deliver_later
        end
      end
    end

    # Daily: memberships past their end expire; reminders go 30 and 7 days
    # before the end to anyone who can renew.
    def self.sweep!(today = Date.current)
      TicketMembership.active.where("ends_on < ?", today).find_each { |m| m.update!(status: "expired") }
      TicketMembership.active.includes(:level).where("ends_on <= ?", today + 30).find_each do |m|
        next unless m.holder_email.present? && m.level.status == "on_sale"

        due = m.days_left(today) <= 7 ? 2 : 1
        next if m.renewal_reminders >= due

        m.update!(renewal_reminders: due)
        TicketMembershipMailer.renewal(m).deliver_later
      end
    end

    # The seats a members-only block gives this member: free seats held for
    # members in the type's zone, best first, let go of the hold so the
    # checkout can take them.
    def self.members_block_seats!(listing, tier, count)
      ids = tier.base_tier.zone_sections.map(&:id)
      rows = TicketSeatHoldSeat.joins(:ticket_seat_hold, :seat).merge(TicketSeatHold.live).where(ticket_listing_id: listing.id, ticket_seat_holds: { kind: "members" })
                               .where(seats: { seat_section_id: ids, killed: false }).order("seats.best_rank").limit(count).to_a
      TicketSeatHoldSeat.where(id: rows.map(&:id)).delete_all
      rows.map(&:seat_id)
    end

    # One zone up (the next dearer seated type) for a member whose level
    # upgrades: the best seats free there, as many as the party.
    def self.upgrade_seats(listing, tier, count, seating:)
      seated = listing.ticket_tiers.active.reject(&:bundle?).select(&:seated_zone?)
      upper = seated.select { |t| t.price_cents > tier.base_tier.price_cents }.min_by(&:price_cents)
      return [] unless upper

      pick = BestAvailable.pick(listing, upper, count, seating: seating)
      pick ? pick.seats.map(&:id) : []
    end
  end
end
