# frozen_string_literal: true

# A contract settlement that was already paid when its Settle up day was
# reopened (Tim, 2026-11-04: paid means paid another way or on a payout run
# that was submitted; CocoScout is the payroll, and an overpayment comes out
# of their next pay). The paid settlement stays exactly as it was paid. When
# the show's ticket money now makes their share a different amount, the
# difference is a payment of its own on the contract, pointing back at the
# settlement (ContractPayment#correction_of):
#
#   more owed   an outgoing payment, which rides the draft payout run when
#               the day settles like any other payment due that day
#   overpaid    a charge settled out of their payout: it nets out of the
#               contract's next share the way a service charge does
#               (ContractorPayoutRunService#apply_service_deductions!),
#               carrying a balance forward when one share can't cover it
#
# A correction that was itself paid counts as paid; one still pending is
# replaced each time the difference is worked out again.
class ContractSettlementCorrection
  # The settlement can be corrected: ours to pay, already paid, and worked
  # out from ticket sales (anything else has no "now" to compare with).
  def self.applies?(payment)
    payment.direction_outgoing? && !payment.correction? && payment.paid_or_submitted? &&
      ContractPaymentSyncService.current_amount(payment).present?
  end

  # What the settlement comes to now, less what was paid for it (the
  # settlement and any corrections already paid). Positive is more owed,
  # negative is overpaid. Nil when the settlement can't be corrected.
  def self.outstanding_cents(payment)
    return nil unless applies?(payment)

    now = (ContractPaymentSyncService.current_amount(payment).to_d * 100).round
    paid = cents(payment) + payment.corrections.select(&:paid_or_submitted?).sum { |c| signed_cents(c) }
    now - paid
  end

  # The correction still to settle for this settlement, if any.
  def self.pending(payment) = payment.corrections.reject(&:paid_or_submitted?).reject(&:status_cancelled?)

  # Bring the settlement's pending correction in line with the difference
  # as it stands: none when there's no difference, else one payment for it.
  # Returns the pending correction, or nil.
  def self.sync!(payment)
    difference = outstanding_cents(payment)
    return nil if difference.nil?

    ActiveRecord::Base.transaction do
      clear_pending!(payment)
      next nil if difference.zero?

      label = payment.show&.date_and_time&.strftime("%b %-d") || payment.due_date.strftime("%b %-d")
      money = ActiveSupport::NumberHelper.number_to_currency(difference.abs / 100.0)
      was = ActiveSupport::NumberHelper.number_to_currency(payment.amount)
      payment.contract.contract_payments.create!(
        correction_of: payment, show_id: payment.show_id, due_date: payment.due_date, amount: difference.abs / 100.0,
        direction: difference.positive? ? "outgoing" : "incoming",
        settlement_method: difference.positive? ? "direct" : "payout_deduction",
        description: difference.positive? ? "Correction for #{label}: more owed" : "Correction for #{label}: paid over",
        notes: "#{label} was reopened after its #{was} settlement was paid. Ticket sales now make it #{money} #{difference.positive? ? 'more' : 'less'}. " +
               (difference.positive? ? "The difference rides the next payout run." : "The difference comes out of their next share.")
      )
    end
  end

  # The day was reopened: a correction nobody has paid yet goes, off the
  # draft run first; it is worked out again when the day settles.
  def self.clear_pending!(payment)
    pending(payment).each do |correction|
      ContractorPayoutRunService.remove_contract_payment!(correction) if correction.in_payout_run?
      correction.reload.destroy!
    end
    payment.corrections.reset
  end

  def self.cents(payment) = (payment.amount.to_d * 100).round
  def self.signed_cents(correction) = correction.direction_outgoing? ? cents(correction) : -cents(correction)
end
