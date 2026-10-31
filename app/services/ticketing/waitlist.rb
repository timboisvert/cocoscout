# frozen_string_literal: true

module Ticketing
  # The waitlist for a sold-out date (advanced ticketing plan §7b): joining,
  # offering returned seats to the first party that fits, and the sweep that
  # passes a missed offer to the next person. Notices go by email only (D6).
  #
  # An offer is an ordinary checkout (TicketCheckout.start!) whose hold is
  # stretched to the offer window, so the seats are counted as taken by
  # Inventory like any other hold, and paying it settles like any sale.
  class Waitlist
    class Error < StandardError; end

    # Can people join this date's list right now? Only when it's sold out,
    # still selling, and its production has the waitlist on.
    def self.open?(listing, inventory = listing.inventory)
      listing.production_ticketing&.waitlist? && listing.selling? && inventory.sold_out? && !listing.show.canceled
    end

    def self.join!(listing, name:, email:, phone: nil, quantity: 1, preference: "any")
      raise Error, "This date isn't taking a waitlist right now." unless open?(listing)

      entry = listing.waitlist_entries.create!(name: name, email: email, phone: phone.to_s.strip.presence, quantity: quantity.to_i.clamp(1, TicketWaitlistEntry::MAX_QUANTITY),
                                               preference: preference.presence_in(TicketWaitlistEntry::PREFERENCES.keys) || "any")
      TicketWaitlistMailer.joined(entry).deliver_later
      entry
    rescue ActiveRecord::RecordInvalid => e
      raise Error, e.record.errors.full_messages.to_sentence
    end

    def self.leave!(entry)
      return entry unless entry.live?

      entry.transaction do
        release_offer!(entry) if entry.offered?
        entry.update!(status: "removed")
      end
      entry
    end

    # Seats came back on a date: offer them to the first waiting party that
    # fits, then the next, while seats last. Each offer takes the cheapest
    # ticket type on sale that fits the party.
    def self.offer_returned_seats!(listing)
      return [] unless listing.production_ticketing&.waitlist? && listing.selling? && !listing.show.canceled

      offered = []
      listing.waitlist_entries.waiting.to_a.each do |entry|
        order = offer!(entry)
        offered << entry if order
        break if listing.inventory.sold_out?
      end
      offered
    end

    # One party's offer: a checkout held for the offer window, emailed. Nil
    # when the party doesn't fit (it keeps waiting).
    def self.offer!(entry)
      listing = entry.ticket_listing
      tier = tier_for(listing, entry.quantity)
      return nil unless tier

      order = nil
      entry.with_lock do
        return nil unless entry.waiting?

        order = TicketCheckout.start!(listing: listing, quantities: { tier.id => entry.quantity }, channel: "online")
        expires = TicketWaitlistEntry::OFFER_WINDOW.from_now
        order.update!(expires_at: expires, buyer_name: entry.name, buyer_email: entry.email, buyer_phone: entry.phone, waitlist_offer: true)
        order.ticket_purchase&.update!(expires_at: expires)
        entry.update!(status: "offered", offered_at: Time.current, offer_expires_at: expires, offer_order: order)
      end
      TicketWaitlistMailer.offer(entry).deliver_later
      order
    rescue TicketCheckout::Error
      nil
    end

    # The sweep (WaitlistOfferJob, every few minutes and on every seat-return
    # event): offers that were paid are bought; offers that lapsed are missed
    # and their seats go to the next person.
    def self.sweep!(listing = nil)
      scope = TicketWaitlistEntry.offered.includes(:offer_order, ticket_listing: { show: {}, production: :production_ticketing })
      scope = scope.where(ticket_listing_id: listing.id) if listing
      touched = Set.new
      scope.find_each do |entry|
        order = entry.offer_order
        if order&.paid?
          entry.update!(status: "bought")
        elsif order.nil? || !order.pending? || order.hold_expired?
          entry.update!(status: "missed")
          TicketWaitlistMailer.missed(entry).deliver_later
          touched << entry.ticket_listing
        end
      end
      listings = listing ? [ listing ] : touched.to_a + TicketWaitlistEntry.waiting.includes(ticket_listing: { show: {}, production: :production_ticketing }).map(&:ticket_listing).uniq
      listings.uniq.each { |l| offer_returned_seats!(l) }
    end

    # An offer's checkout was paid.
    def self.bought!(order)
      return unless order.waitlist_offer?

      TicketWaitlistEntry.offered.where(offer_order_id: order.id).update_all(status: "bought", updated_at: Time.current)
    end

    # The box office's note to everyone waiting (a nearby date opened, say):
    # the edited draft, {{first_name}} filled per person.
    def self.send_note!(entries, subject:, body:)
      entries.each do |entry|
        TicketWaitlistMailer.note(entry, subject: subject.gsub("{{first_name}}", entry.first_name.to_s), body: body.gsub("{{first_name}}", entry.first_name.to_s)).deliver_later
      end
      entries.size
    end

    # The cheapest ticket type selling online with room for the party.
    def self.tier_for(listing, quantity)
      inventory = listing.inventory
      listing.ticket_tiers.active.reject(&:bundle?).reject(&:hidden?).select(&:selling?)
             .select { |tier| (left = inventory.remaining(tier: tier)).nil? || left >= quantity }
             .min_by(&:price_cents)
    end

    def self.release_offer!(entry)
      order = entry.offer_order
      return unless order&.pending?

      order.ticket_purchase ? order.ticket_purchase.expire! : order.update!(status: "expired", expires_at: Time.current)
    end
    private_class_method :tier_for, :release_offer!
  end
end
