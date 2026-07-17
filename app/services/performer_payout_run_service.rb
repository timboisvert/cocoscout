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
    def add_show_payout!(show_payout, added_by: nil)
      organization = show_payout.show.production.organization
      added = 0
      skipped = 0
      batch = nil

      ActiveRecord::Base.transaction do
        batch = PayoutBatch.open_for(organization, kind: "performer", created_by: added_by)
        label = label_for(show_payout.show)

        show_payout.line_items.includes(:payee).each do |line|
          cents = (line.amount.to_d * 100).round
          if !payable?(line) || cents <= 0 || PayoutContribution.exists?(source: line)
            skipped += 1
            next
          end

          item = batch.items.find_by(payee: line.payee)
          if item
            add_contribution(batch, item, line, cents, label)
            item.update!(amount_cents: item.payout_contributions.sum(:amount_cents))
          else
            item = batch.items.create!(payee: line.payee, amount_cents: cents, status: "pending")
            add_contribution(batch, item, line, cents, label)
          end
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

    # Individuals who carry a Stripe payout account (Person / Contractor). Guests
    # (no payee) and groups are handled offline for now.
    def payable?(line)
      line.payee.present? && line.payee.respond_to?(:can_receive_payouts?)
    end

    def label_for(show)
      return show.name_with_date if show.respond_to?(:name_with_date)

      show.date_and_time&.strftime("%b %-d, %Y") || "Show payout"
    end
  end
end
