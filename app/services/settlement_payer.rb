# frozen_string_literal: true

# Paying people from the day (Tim, 2026-11-04): the day's page works out who
# gets paid from each show as soon as its money is confirmed, the manager's
# choices are kept on the lines, and settling the day is what puts them on
# the organization's open payout run. Nothing rides the run before the day
# is settled; reopening it takes back whatever is still on a draft.
#
#   SettlementPayer.calculate!(show)      # the show's money was confirmed: work out its payout
#   SettlementPayer.stage!(day, by:)      # the day settled: every "on the run" line goes on the open run
#   SettlementPayer.unstage!(day)         # the day reopened: lines still on a draft come back off
class SettlementPayer
  Staged = Data.define(:count, :cents, :notes) do
    def any? = count.positive?
    def words = "#{ActiveSupport::NumberHelper.number_to_currency(cents / 100.0)} for #{count} #{'person'.pluralize(count)}"
  end

  # Work out a show's performer payout from the numbers as they stand (the
  # Calculate step on the day), keeping any choice already made on its lines
  # (a hold stays a hold). Lines already paid or on a run are never rebuilt
  # from under anyone. Answers { success:, total:, line_items: } or
  # { success: false, error: } the way PayoutCalculator does.
  def self.calculate!(show)
    organization = show.production.organization
    pay = SettleUp.pay_for(organization, show)
    return { success: false, error: "nothing to work out" } unless pay.performers? && pay.scheme
    return { success: false, error: "nobody is cast on it" } if pay.calc == :no_cast
    return { success: false, error: pay.hold_reason.downcase } if pay.held? && !pay.can_calculate?

    payout = show.show_payout
    payout = show.create_show_payout!(payout_scheme: pay.scheme, status: "awaiting_payout") unless payout&.persisted?
    return { success: false, error: "lines are already paid or on a run" } if payout.line_items.any? { |line| line.paid? || line.in_payout_run? }

    rules = payout.resolved_rules
    return { success: false, error: "the calculation has no rules" } if rules.blank?

    payout.update!(act_counts: show.lineup_act_counts) if rules.dig("distribution", "method").to_s == "per_act" && show.act_based?
    result = payout.keeping_pay_choices { PayoutCalculator.calculate(show: show, rules: rules, act_counts: payout.act_counts) }
    return result unless result[:success]

    show.reload
    payout.update!(calculated_at: Time.current, total_payout: result[:total])
    result
  end

  # Settling: each show's lines chosen for the run go on the open run, and
  # each contract show's share due for the night. Returns what went on.
  def self.stage!(day, by: nil)
    count = 0
    cents = 0
    notes = []
    day.shows.each do |piece|
      pay = piece.pay
      if pay.performers? && pay.show_payout&.calculated_at.present?
        lines = pay.show_payout.line_items.includes(:payee).select(&:rides_on_settle?)
        next if lines.empty?

        PerformerPayoutRunService.add_show_payout!(pay.show_payout, added_by: by, only_line_ids: lines.map(&:id))
        lines.each do |line|
          if PayoutContribution.exists?(source: line)
            count += 1
            cents += (line.net_amount.to_d * 100).round
          else
            notes << "#{line.payee_name} can't be paid through a run yet (#{line.is_guest? ? 'a guest with no CocoScout account' : 'a group'})."
          end
        end
      elsif pay.contract?
        pay.payments.each do |payment|
          next unless stageable?(payment)

          result = ContractorPayoutRunService.add_contract_payment!(payment, added_by: by)
          if result.added
            count += 1
            cents += (payment.amount.to_d * 100).round
          elsif result.error.present? && result.error != "already_added"
            notes << "#{payment.display_name}: #{result.error}"
          end
        end
      end
    end
    Staged.new(count: count, cents: cents, notes: notes)
  end

  # Reopening: whatever this day put on a run that's still a draft comes
  # back off (the run re-totals); money already funded or sent stays, and
  # the difference rides the next run when the day settles again (§9.7).
  def self.unstage!(day)
    count = 0
    cents = 0
    day.shows.each do |piece|
      pay = piece.pay
      if pay.performers? && pay.show_payout
        pay.show_payout.line_items.each do |line|
          contribution = PayoutContribution.find_by(source: line)
          next unless contribution && PayoutRunRemoval.removable?(contribution)

          PayoutRunRemoval.remove!(contribution)
          count += 1
          cents += (line.net_amount.to_d * 100).round
        end
      elsif pay.contract?
        pay.payments.each do |payment|
          contribution = PayoutContribution.find_by(source: payment)
          next unless contribution && PayoutRunRemoval.removable?(contribution)

          ContractorPayoutRunService.remove_contract_payment!(payment)
          count += 1
          cents += (payment.amount.to_d * 100).round
        end
      end
    end
    Staged.new(count: count, cents: cents, notes: [])
  end

  # A contract payment that rides the run when the day settles: money we owe,
  # still pending, with an amount, due (a settlement for a show still to come
  # waits), not on a run yet, and a person behind the contractor to pay.
  def self.stageable?(payment)
    payment.direction_outgoing? && payment.status_pending? && payment.amount.to_f.positive? &&
      !payment.settles_after_show? && !payment.in_payout_run? && payment.contract&.contractor&.person.present?
  end
end
