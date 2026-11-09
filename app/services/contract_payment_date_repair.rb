# frozen_string_literal: true

# One pass (2026-11-08) for payments a moved date left behind.
#
# Moving a date used to move only the payments linked to its show. A fee or a
# service charge nobody had linked stayed on the old date, where the contract
# no longer has a night, and went overdue there (Full Five Fridays: "Event 10
# Fee" still due Nov 6 after the show moved to Nov 20). The ones that did move
# kept the old date in their name ("Jan 16 — 50% to them", due Jan 15).
# ContractDateChanges.retime! does both properly now; this puts right what it
# left behind.
#
# Careful on purpose: it only touches pending payments that aren't in a payout
# run, only ones that are plainly a night's own (a per-event service's charge,
# a per-event fee, or one of a kind the contract's other nights each have; a
# deposit due weeks ahead is nobody's leftover), only moves one when there is
# exactly one place for it to go, and says every change it makes. A night's
# payment it can't place it reports and leaves. Safe to run again: a repaired
# payment no longer matches.
class ContractPaymentDateRepair
  # A night rarely moves further than this; a payment further away from every
  # open date is somebody's on-purpose schedule, not a leftover.
  WINDOW = 45

  Change = Struct.new(:contract_id, :payment_id, :was, :now, keyword_init: true)
  Result = Struct.new(:changes, :unplaced, keyword_init: true)

  NAMED_FOR_A_DATE_FIRST = /\A([A-Z][a-z]{2} \d{1,2}) — /
  NAMED_FOR_A_DATE_LAST = / — ([A-Z][a-z]{2} \d{1,2}, \d{4})\z/
  # What the contract wizard calls a per-event deal's payments.
  PER_EVENT_NAME = /\A(?:Event \d+ Fee|[A-Z][a-z]{2} \d{1,2} event)\z/i

  class << self
    def run!(dry_run: false)
      result = Result.new(changes: [], unplaced: [])

      Contract.where(status: "active").includes(:contract_payments, :space_rentals).find_each do |contract|
        next if contract.space_rentals.empty?

        ActiveRecord::Base.transaction do
          move_left_behind(contract, result, dry_run)
          rename_moved(contract, result, dry_run)
        end
      end

      result
    end

    private

    # A payment is left behind when it falls due on a day this contract has
    # nothing on. It goes to a night that has no payment of its kind, when the
    # leftovers and the open nights pair off one for one, in date order.
    def move_left_behind(contract, result, dry_run)
      nights = contract.space_rentals.map { |rental| rental.effective_event_starts_at.to_date }.uniq.sort
      occupied = (nights + contract.space_rentals.map { |rental| rental.starts_at.to_date } +
                  contract.contract_shows.pluck(:date_and_time).compact.map(&:to_date)).to_set
      live = contract.contract_payments.reject(&:status_cancelled?)

      leftovers = live.select do |payment|
        payment.status_pending? && payment.show_id.nil? && !payment.in_payout_run? &&
          !contract.period_settlement?(payment) && !occupied.include?(payment.due_date)
      end

      leftovers.group_by { |payment| kind(payment) }.each do |kind, payments|
        siblings = live.select { |payment| kind(payment) == kind }
        service_nights = service_nights_for(contract, kind)
        next unless service_nights || siblings.any? { |payment| occupied.include?(payment.due_date) } ||
                    (contract.draft_payment_structure == "per_event" && payments.all? { |payment| payment.description.to_s.match?(PER_EVENT_NAME) })

        payments = payments.sort_by(&:due_date)
        taken = siblings.map(&:due_date).to_set
        open = (service_nights || nights).reject { |night| taken.include?(night) }
                                         .select { |night| payments.any? { |payment| (night - payment.due_date).abs <= WINDOW } }

        pairs = payments.zip(open)
        unless open.size == payments.size && pairs.all? { |payment, night| (night - payment.due_date).abs <= WINDOW }
          payments.each { |payment| result.unplaced << describe(contract, payment) }
          next
        end

        pairs.each do |payment, night|
          was = describe(contract, payment)
          if dry_run
            result.changes << Change.new(contract_id: contract.id, payment_id: payment.id, was: was, now: "due #{night}")
          else
            ContractDateChanges.redate_payment!(payment, night)
            result.changes << Change.new(contract_id: contract.id, payment_id: payment.id, was: was, now: describe(contract, payment))
          end
        end
      end
    end

    # A payment that moved with its show but still names the old date.
    def rename_moved(contract, result, dry_run)
      contract.contract_payments.each do |payment|
        next unless payment.status_pending? && payment.show_id.present? && !payment.in_payout_run?
        next if contract.period_settlement?(payment)

        night = payment.show&.date_and_time&.to_date
        next unless night && night == payment.due_date

        named = named_date(payment.description, near: night)
        next if named.nil? || named == night || (named - night).abs > WINDOW

        was = describe(contract, payment)
        name = ContractDateChanges.redated_text(payment.description, { named => night })
        payment.update!(description: name) unless dry_run
        result.changes << Change.new(contract_id: contract.id, payment_id: payment.id, was: was,
                                     now: "\"#{name}\" due #{payment.due_date}")
      end
    end

    # The date a generated name carries: "Jan 16 — 50% to them" (no year, so
    # the one nearest the night) or "Booth Tech — Jan 16, 2027". Hand-written
    # names are never read for dates.
    def named_date(description, near:)
      text = description.to_s
      if (match = text.match(NAMED_FOR_A_DATE_LAST))
        Date.parse(match[1]) rescue nil
      elsif (match = text.match(NAMED_FOR_A_DATE_FIRST))
        [ near.year - 1, near.year, near.year + 1 ]
          .filter_map { |year| Date.parse("#{match[1]}, #{year}") rescue nil }
          .min_by { |date| (date - near).abs }
      end
    end

    # The nights a per-event service is billed for, when `kind` is one's
    # charges: the service's own list, which the old move did keep in step.
    def service_nights_for(contract, kind)
      line = contract.draft_services.find { |service| service["per_event"] && service["name"].to_s.gsub(/\d+/, "").squish == kind.last }
      return nil unless line

      Array(line["events"]).filter_map { |event| (Time.zone.parse(event["starts_at"].to_s) rescue nil)&.to_date }.uniq.sort
    end

    # What a payment is, apart from which night it's for: "Event 10 Fee" and
    # "Event 11 Fee" are the same kind, and so are a service's charges
    # ("Booth Tech — Jan 16, 2027").
    def kind(payment)
      [ payment.direction,
        payment.description.to_s.sub(NAMED_FOR_A_DATE_LAST, "").sub(NAMED_FOR_A_DATE_FIRST, "").gsub(/\d+/, "").squish ]
    end

    def describe(contract, payment)
      "contract #{contract.id} (#{contract.display_name}): \"#{payment.description}\" due #{payment.due_date}"
    end
  end
end
