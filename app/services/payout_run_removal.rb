# frozen_string_literal: true

# Taking one thing back out of a draft payout run, whatever kind of money it
# is (Tim, 2026-10-11: "the behavior should be the same whether it's a
# contract or not"). Nothing has been funded on a draft, so each kind is
# undone the way it went in:
#
#   contract payment   its line and the charges netted out of it on this run
#                      (those go back to owed); it then catches up with ticket
#                      sales since (ContractorPayoutRunService)
#   show payout        that payee's lines for the show (still owed; add back
#                      from the show's payout page), as the show page does
#   course payout      its line (still owed)
#   staff pay          that person's whole staff pay on this run: their hours
#                      go back to waiting, and their bonus, reimbursement and
#                      tips go back into Pay People, as discarding the run does
#                      for everyone
#   balance payout     its line
#
# Advances and the organization's own remainder stay put: they come off by
# discarding the run.
class PayoutRunRemoval
  Result = Data.define(:notice, :error)

  def self.removable?(contribution)
    batch = contribution.payout_batch
    return false unless batch&.open? && !contribution.payout_batch_item&.paid?
    return false if contribution.payee_type == "Organization" || contribution.source_type == "PersonAdvance"
    return false if contribution.source_type == "ContractPayment" && contribution.amount_cents.negative?

    true
  end

  def self.remove!(contribution)
    return Result.new(notice: nil, error: "Only something in a draft run can come out.") unless removable?(contribution)

    batch = contribution.payout_batch
    payee = contribution.payee&.try(:name) || "They"
    if contribution.source_type == "ContractPayment"
      result = ContractorPayoutRunService.remove_contract_payment!(contribution.source)
      return Result.new(notice: nil, error: result.error) if result.error

      payment = contribution.source.reload
      amount = payment.amount_tbd? ? "its amount is waiting on ticket sales" : "it's now #{money(payment.amount)}"
      return Result.new(notice: "Took #{payment.display_name} out of the run; #{amount}. Add it again from the contract.", error: nil)
    end

    if contribution.category == "staffing"
      remove_staff_pay!(contribution.payout_batch_item)
      return Result.new(notice: "Took #{payee}'s staff pay out of the run. Their hours and amounts are back in Pay People.", error: nil)
    end

    ActiveRecord::Base.transaction do
      siblings(contribution).each(&:destroy!)
      batch.reload.recalculate_total! if PayoutBatch.exists?(batch.id)
    end
    Result.new(notice: "Took #{contribution.label} out of the run. #{payee} is still owed it; add it back anytime.", error: nil)
  end

  # What comes out with it: a show payout's other lines for the same payee
  # (several allocations come out together), else just this line.
  def self.siblings(contribution)
    return [ contribution ] unless contribution.source_type == "ShowPayoutLineItem" && contribution.source

    line = contribution.source
    ids = ShowPayoutLineItem.where(show_payout_id: line.show_payout_id, payee_type: line.payee_type, payee_id: line.payee_id).ids
    PayoutContribution.where(payout_batch_item_id: contribution.payout_batch_item_id, source_type: "ShowPayoutLineItem", source_id: ids).to_a
  end

  def self.remove_staff_pay!(item)
    batch = item.payout_batch
    ActiveRecord::Base.transaction do
      PayoutBatchService.return_staff_pay_to_draft!(batch, item)
      batch.staff_time_entries.where(person_id: item.payee_id).update_all(payout_batch_id: nil, paid_at: nil, updated_at: Time.current)
      item.payout_contributions.select { |c| c.category == "staffing" }.each(&:destroy!)
      batch.reload.recalculate_total! if PayoutBatch.exists?(batch.id)
    end
  end

  def self.money(amount)
    ActiveSupport::NumberHelper.number_to_currency(amount)
  end

  private_class_method :siblings, :remove_staff_pay!, :money
end
