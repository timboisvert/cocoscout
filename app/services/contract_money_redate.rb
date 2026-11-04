# frozen_string_literal: true

# One pass (2026-11-02) that moves contract money already on the books to the
# date it's for. Books used to date it the day it was paid, so October
# rehearsals paid on November 1 counted as November income when earned. Each
# posting is restated through its own poster; a date-only change reverses on
# the old entry's own dates (LedgerPosting), so no month gains or loses money
# it never had. Safe to run again: unchanged postings are left alone.
class ContractMoneyRedate
  def self.run!
    live = JournalEntry.where(reversed_at: nil, reversal_of_id: nil)
    before = JournalEntry.count

    paid_outside = live.where(source_type: "ContractPayment", kind: "contract_payment").select(:source_id)
    ContractPayment.where(id: paid_outside).find_each { |payment| BooksOutsidePoster.post_contract_payment!(payment) }

    collected = OrgCashEntry.where(source_type: "ContractPayment", id: live.where(source_type: "OrgCashEntry").select(:source_id))
    collected.find_each { |entry| BooksPoster.post!(entry) }

    shares = PayoutLedgerEntry.where(source_type: "PayoutContribution",
                                     source_id: PayoutContribution.where(source_type: "ContractPayment").select(:id),
                                     id: live.where(source_type: "PayoutLedgerEntry").select(:source_id))
    shares.find_each { |entry| BooksPoster.post!(entry) }

    # Each re-dated posting writes a reversal and a new entry.
    (JournalEntry.count - before) / 2
  end
end
