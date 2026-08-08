# frozen_string_literal: true

# Adding, removing and moving the dates on a contract, without touching the deal.
#
# The old path for this was the full amend wizard, which regenerated the whole
# payment schedule from the deal and so invented a second payment for any date
# that had already been settled. Changing a date should change that date and
# the money that depends on it — nothing else.
class ContractDateChanges
  class << self
    # A date that's been paid for, or is committed to a payout run, can only be
    # cancelled — never deleted. The show stays as a cancelled record, the money
    # that already moved stays put, and only still-pending payments drop off.
    def remove!(contract:, rental:)
      shows = shows_for(contract, rental)
      settled = settled_for?(contract: contract, rental: rental, shows: shows)
      label = rental.starts_at.strftime("%b %-d")

      dropped = drop_pending_payments!(contract, rental, shows)

      if settled
        # Cancel, keep the record: money that already moved has to stay
        # attributable to a real show. update! rather than update_all so the
        # contract-payment sync hook still sees it.
        shows.each do |show|
          # Pin the show's own span before the rental goes — without a
          # duration of its own it reads its end time off the rental, and
          # would lose it.
          show.duration_minutes ||= rental.effective_duration_minutes
          show.canceled = true
          show.save!
        end
      else
        Show.without_contract_payment_sync do
          shows.each(&:destroy!)
        end
      end

      # Either way the date is off the contract, so the room is free again. A
      # cancelled date that keeps its booking holds the space against everyone
      # else — the overlap check still counts it — and reads as confirmed on
      # the contract page, which is how this looked like nothing happened.
      rental.destroy!

      { label: label, settled: settled, dropped: dropped }
    end

    # Reschedule in place: the show keeps its identity, so its cast, its
    # staffing shifts and its payment all follow it rather than being rebuilt.
    def move!(contract:, rental:, starts_at:, ends_at:)
      shows = shows_for(contract, rental)
      offset = starts_at - rental.starts_at

      rental.update!(starts_at: starts_at, ends_at: ends_at,
                     event_starts_at: rental.event_starts_at ? rental.event_starts_at + offset : nil,
                     event_ends_at: rental.event_ends_at ? rental.event_ends_at + offset : nil)

      shows.each { |show| show.update!(date_and_time: show.date_and_time + offset) }

      # Pending payments tied to those shows move with them; paid ones are
      # history and keep the date they were actually settled on.
      contract.contract_payments.status_pending.where(show_id: shows.map(&:id)).find_each do |payment|
        payment.update!(due_date: (payment.due_date + offset.seconds.to_i.seconds).to_date)
      end

      starts_at.strftime("%b %-d")
    end

    # Has money actually moved for this date? A paid payment, a payment
    # committed to a payout run, or real revenue recorded against the show.
    #
    # Public because the Change dates screen has to warn about exactly the same
    # dates this method will refuse to delete — a second copy of the rule in the
    # view is a promise the service doesn't keep.
    def settled_for?(contract:, rental:, shows: nil)
      shows ||= shows_for(contract, rental)
      payments = contract.contract_payments.where(show_id: shows.map(&:id)).to_a
      payments += contract.contract_payments.where(due_date: rental.starts_at.to_date).to_a

      payments.any? { |p| p.status_paid? || p.in_payout_run? } ||
        shows.any? { |s| financials_settled?(s) }
    end

    private

    def shows_for(contract, rental)
      return [] unless contract.production

      contract.production.shows.where(space_rental_id: rental.id).to_a
    end

    # A ShowFinancials row on its own proves nothing — one gets created just by
    # opening a show's payout page. It's only settled once someone confirmed the
    # numbers or entered actual revenue. Treating the bare row as settled meant a
    # future show nobody had paid a cent for couldn't be deleted.
    def financials_settled?(show)
      financials = show.show_financials
      return false unless financials

      financials.data_confirmed? ||
        financials.ticket_revenue.to_f.positive? ||
        financials.flat_fee.to_f.positive?
    end

    # Only pending, uncommitted payments for this date come off. Anything paid
    # or already in a run is left exactly as it is.
    def drop_pending_payments!(contract, rental, shows)
      scope = contract.contract_payments.status_pending.where(show_id: shows.map(&:id))
      by_date = contract.contract_payments.status_pending
                        .where(show_id: nil, due_date: rental.starts_at.to_date)

      (scope.to_a + by_date.to_a).uniq.reject(&:in_payout_run?).each(&:destroy!).size
    end
  end
end
