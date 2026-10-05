# frozen_string_literal: true

module Courses
  # One course's numbers, the way Ticketing::ListingStats is for a show:
  # registered of capacity, sales, what the theater keeps, refunds. The
  # course page's tiles read it, so no two screens disagree.
  class OfferingStats
    attr_reader :offering

    def initialize(offering)
      @offering = offering
      @registrations = offering.course_registrations.to_a
    end

    def confirmed = @registrations.select(&:confirmed?)
    def refunded = @registrations.select(&:refunded?)
    def registered = confirmed.size
    def capacity = offering.capacity

    def spots_left
      capacity && [ capacity - offering.effective_registrations_count, 0 ].max
    end

    # Before tax.
    def sales_cents = confirmed.sum { |r| r.amount_cents.to_i }
    def tax_cents = confirmed.sum { |r| r.tax_cents.to_i }

    # After CocoScout's fee and Stripe's; money paid by hand is kept whole.
    def net_cents
      confirmed.sum { |r| r.amount_cents.to_i - r.cocoscout_fee_cents.to_i - r.stripe_fee_cents.to_i }
    end

    def refunded_cents = refunded.sum { |r| r.amount_cents.to_i + r.tax_cents.to_i }
    def by_hand = confirmed.count { |r| r.channel == "manual" }
  end
end
