# frozen_string_literal: true

# Adds a show's calculated performer payouts to the organization's open
# "performer" payout run. One PayoutBatchItem per payee (their running total =
# one Stripe transfer), with a PayoutContribution per show — so a performer in
# four weekend shows ends up as one item with four contributions.
#
# Idempotent per show-payout line (unique source), so re-adding the same show
# doesn't double-count. Only individual payees who can be paid through Stripe are
# added; guests and groups are skipped (paid offline for now).
class PerformerPayoutRunService
  Result = Struct.new(:batch, :added, :skipped, keyword_init: true)

  class << self
    # only_line_ids: the picker's checkbox selection — when given, lines not in
    # the list stay off the run (the manager plans to pay them another way).
    def add_show_payout!(show_payout, added_by: nil, only_line_ids: nil)
      organization = show_payout.show.production.organization
      added = 0
      skipped = 0
      batch = nil

      ActiveRecord::Base.transaction do
        batch = PayoutBatch.open_for(organization, kind: "performer", created_by: added_by)
        # Make sure the ledger reflects every earning before we settle to net
        # balance (idempotent).
        show_payout.sync_earnings_to_ledger!
        label = label_for(show_payout.show)

        show_payout.line_items.includes(:payee).each do |line|
          cents = (line.amount.to_d * 100).round
          if (only_line_ids && !only_line_ids.include?(line.id)) ||
             !payable?(line) || cents <= 0 || PayoutContribution.exists?(source: line)
            skipped += 1
            next
          end

          item = batch.items.find_by(payee: line.payee) ||
                 batch.items.create!(payee: line.payee, amount_cents: cents, status: "pending")
          add_contribution(batch, item, line, cents, label)
          # Item pays the payee's net performer balance, so advances net against
          # earnings automatically.
          item.settle_performer_amount!
          added += 1
        end

        batch.recalculate_total!
      end

      Result.new(batch: batch, added: added, skipped: skipped)
    end

    private

    def add_contribution(batch, item, line, cents, label)
      PayoutContribution.create!(
        payout_batch: batch, payout_batch_item: item, payee: line.payee,
        source: line, amount_cents: cents, label: label, description: line.payee.try(:name)
      )
    end

    # Anyone who CAN eventually be paid through Stripe goes on the run — same
    # model as staffing: no-bank people ride along, the funded run holds their
    # money, and "Pay remaining" sends it once they connect. Guests (no payee —
    # they'd have to become a Person first) and groups stay offline.
    def payable?(line)
      line.payee.present? && PayoutBatchService::PAYABLE_TYPES.include?(line.payee_type)
    end

    def label_for(show)
      return show.name_with_date if show.respond_to?(:name_with_date)

      show.date_and_time&.strftime("%b %-d, %Y") || "Show payout"
    end
  end
end
