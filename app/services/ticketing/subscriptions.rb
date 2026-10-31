# frozen_string_literal: true

module Ticketing
  # Season subscriptions (advanced ticketing §2a): the same seats on every
  # date of a subscription pass, bought as one dated pass (one order per
  # show, the money as any pass); renewal by invitation, with each
  # subscriber's seats held on next season's dates until the close.
  class Subscriptions
    class Error < StandardError; end

    # Seats a new subscriber may pick: free on every date, in each date's
    # ticket type's zone, best first.
    def self.free_seats(pass, rows = pass.rows)
      return [] if rows.empty? || rows.any? { |r| !r.ticket_listing.seated? }

      per_date = rows.map do |row|
        seating = Seating.new(row.ticket_listing)
        seating.free_seats(row.ticket_tier).reject(&:accessible?).map(&:id)
      end
      ids = per_date.reduce { |a, b| a & b }
      Seat.where(id: ids).includes(:seat_section).sort_by(&:best_rank)
    end

    # Best available across the season: a block together where one exists.
    def self.best_seats(pass, quantity, rows = pass.rows)
      free = free_seats(pass, rows)
      raise Inventory::SoldOut if free.size < quantity

      by_row = free.group_by { |s| [ s.seat_section_id, s.row_label ] }.values
      block = by_row.map { |seats| seats.sort_by(&:number).each_cons(quantity).find { |run| run.each_cons(2).all? { |a, b| b.number - a.number == 1 } } }.compact
                    .min_by { |run| run.sum(&:best_rank) }
      (block || free.first(quantity)).map(&:id)
    end

    # The map for the pass page: every seat on the chart, free when free on
    # every date.
    def self.payload(pass, rows = pass.rows)
      first = rows.first.ticket_listing
      base = Seating.new(first).payload(tiers: rows.select { |r| r.ticket_listing_id == first.id }.map(&:ticket_tier))
      free = free_seats(pass, rows).map(&:id).to_set
      base[:sections].each { |section| section[:seats].each { |seat| seat[:status] = "sold" if seat[:status] == "free" && !free.include?(seat[:id]) } }
      base
    end

    # A subscriber's seats on the way in: picked, held for their renewal,
    # or best available. Called under no lock; reserve_all! checks again.
    def self.seats_for!(pass, quantity, rows, seat_ids: nil, renewing: nil)
      if renewing
        ids = renewing.seat_ids.map(&:to_i)
        raise Error, "Your renewal seats don't match this season's dates." unless ids.size == quantity
        # Let go of the holds so the checkout can take the seats.
        TicketSeatHoldSeat.where(ticket_seat_hold_id: renewing.seat_holds.select(:id), seat_id: ids).delete_all
        return ids
      end
      ids = Array(seat_ids).map(&:to_i).reject(&:zero?).uniq
      return best_seats(pass, quantity, rows) if ids.empty?

      free = free_seats(pass, rows).map(&:id)
      raise Error, "Pick #{quantity} #{'seat'.pluralize(quantity)}." unless ids.size == quantity
      raise Error, "One of those seats isn't free on every date. Pick again." unless (ids - free).empty?

      ids
    end

    def self.settle!(subscription, paid_at:)
      subscription.with_lock do
        next unless subscription.status == "pending"

        order = subscription.ticket_purchase&.ticket_orders&.first
        subscription.update!(status: "active", buyer_name: order&.buyer_name.presence || subscription.buyer_name, buyer_email: order&.buyer_email.presence || subscription.buyer_email)
        if (old = subscription.renewed_from) && old.status.in?(%w[active renewal_open])
          old.update!(status: "renewed")
          old.seat_holds.each(&:release!)
        end
        if subscription.buyer_email.present?
          subscription.update!(follower: Follower.for!(subscription.organization, subscription.buyer_email, name: subscription.buyer_name, consented: false))
          TicketSubscriptionMailer.welcome(subscription).deliver_later
        end
        paid_at
      end
    end

    # Next season's pass renews from last season's: every active subscriber
    # gets their seats held on the new dates (the same seats on the same
    # chart, else the same section, row and number) until the close, and an
    # invitation to renew.
    def self.open_renewal!(pass, closes_at:)
      from = pass.renews_from
      raise Error, "Pick which pass this one renews from." unless from
      raise Error, "A renewal needs a close date in the future." unless closes_at && closes_at > Time.current

      rows = pass.rows
      raise Error, "Put the new season's dates in the pass first." if rows.size < 2

      pass.update!(renewal_closes_at: closes_at)
      invited = 0
      from.subscriptions.where(status: "active").includes(:seat_holds).find_each do |sub|
        ids = matching_seats(sub, rows)
        next if ids.empty?

        TicketSubscription.transaction do
          rows.each do |row|
            hold = row.ticket_listing.seat_holds.create!(organization: pass.organization, name: "#{sub.buyer_name.presence || 'Subscriber'} (renewal)",
                                                         kind: "subscription", release_at: closes_at, ticket_subscription: sub)
            ids.each do |id|
              next if Seating.new(row.ticket_listing).taken?(id)

              hold.hold_seats.create!(ticket_listing: row.ticket_listing, seat_id: id)
            end
          end
          sub.update!(status: "renewal_open", renewal_pass: pass, seat_ids: ids, renewal_reminders: 0)
        end
        TicketSubscriptionMailer.renewal(sub).deliver_later if sub.buyer_email.present?
        invited += 1
      end
      invited
    end

    # The subscriber's seats on the new chart: the same ids when the chart
    # is the same, else by section name, row and number.
    def self.matching_seats(sub, rows)
      chart = rows.first.ticket_listing.effective_seat_chart
      return [] unless chart

      sub.seats.filter_map do |seat|
        next seat.id if seat.seat_section.seat_chart_id == chart.id

        section = chart.sections.find { |s| s.name == seat.seat_section.name }
        section&.seats&.find_by(row_label: seat.row_label, number: seat.number)&.id
      end
    end

    # Daily: reminders 14 and 3 days before the close; after it, holds let go
    # (their release_at did) and the subscription is released.
    def self.sweep!(at = Time.current)
      TicketSubscription.where(status: "renewal_open").includes(:renewal_pass).find_each do |sub|
        closes = sub.renewal_pass&.renewal_closes_at
        next unless closes

        if closes <= at
          sub.update!(status: "released")
          next
        end
        due = closes - at <= 3.days ? 2 : (closes - at <= 14.days ? 1 : 0)
        next if due.zero? || sub.renewal_reminders >= due || sub.buyer_email.blank?

        sub.update!(renewal_reminders: due)
        TicketSubscriptionMailer.renewal(sub).deliver_later
      end
    end
  end
end
