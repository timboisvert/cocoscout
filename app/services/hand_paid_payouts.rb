# frozen_string_literal: true

# Payouts that were paid by hand (Venmo, Zelle, cash, a check) before the
# payout ledger existed. The ledger only learns of a payout line when it is
# calculated or paid, so a line settled before the ledger arrived has no
# earning and no payout on it, and the books, which read the ledger, show
# none of that pay. Financials counted it and Books didn't: at Stars &
# Garters, 528 lines and $22,832, the last paid 2026-08-17 (found
# 2026-11-10 getting 1.3 ready; Tim: "Yes, fix first").
#
# Each line gets what a line paid by hand today gets, from the line's own
# methods: an earning dated the show, and a payout of the same amount dated
# the day it was paid. The two cancel, so nobody is owed a cent more or
# less. post! proves that and raises if anyone's balance moved, which rolls
# the organization back (BooksBackfill posts each in its own transaction).
#
# Left alone:
#   - a line with either row already (the ledger knows it);
#   - a $0 line (nothing to say);
#   - a line on a contract show (a third-party production): what the
#     contractor was paid is the contract's own payment, which the books
#     already carry as Contractor pay, and Financials counts it there too.
#     Posting the old payout line as well would count that money twice
#     (A Random Memory: $855 of lines beside $1,501 of contract payments);
#   - a guest's line: a guest has no account to hang a ledger row on, so
#     their pay stays off the books for now. Counted, so it's reported.
class HandPaidPayouts
  Result = Data.define(:lines, :cents, :people, :zero, :guests, :guest_cents, :contract_lines, :contract_cents)
  class BalanceMoved < StandardError; end

  ON_THE_LEDGER = "EXISTS (SELECT 1 FROM payout_ledger_entries e " \
                  "WHERE e.source_type = 'ShowPayoutLineItem' AND e.source_id = show_payout_line_items.id)"

  # The organization's hand-paid lines the ledger has never heard of.
  def self.missing(organization)
    ShowPayoutLineItem.joins(show_payout: { show: :production })
                      .where(productions: { organization_id: organization.id })
                      .where(manually_paid: true)
                      .where("NOT #{ON_THE_LEDGER}")
  end

  # Puts them on the ledger (and so, through each row, on the books).
  def self.post!(organization)
    before = balances(organization)
    posted = []
    zero = 0
    guests = []
    contract = []
    missing(organization).preload(:payee, show_payout: { show: :production }).find_each do |line|
      next contract << line if line.show_payout.show.production.type_third_party?
      next guests << line unless line.ledger_eligible?
      next zero += 1 if line.net_amount.to_d.zero?

      line.sync_earning_ledger_entry!
      line.sync_payout_ledger_entry!
      posted << line
    end

    after = balances(organization)
    moved = (before.keys | after.keys).reject { |key| before[key].to_i == after[key].to_i }
    raise BalanceMoved, "#{moved.size} balance(s) would change: #{moved.first(3).inspect}" if moved.any?

    Result.new(lines: posted.size, cents: posted.sum { |l| (l.net_amount.to_d * 100).round },
               people: posted.map { |l| [ l.payee_type, l.payee_id ] }.uniq.size, zero: zero,
               guests: guests.size, guest_cents: guests.sum { |l| (l.amount.to_d * 100).round },
               contract_lines: contract.size, contract_cents: contract.sum { |l| (l.amount.to_d * 100).round })
  end

  # What each payee is owed, by the kind of money: the thing that must not move.
  def self.balances(organization)
    PayoutLedgerEntry.where(organization: organization).group(:payee_type, :payee_id, :category).sum(:amount_cents)
  end
end
