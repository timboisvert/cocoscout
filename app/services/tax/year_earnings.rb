# frozen_string_literal: true

module Tax
  # Sums what an org actually paid each staff-category payee in a calendar
  # year, cash basis (by the date money was paid), for 1099-NEC purposes.
  #
  # NEC compensation excludes reimbursements — they're not compensation, just
  # expense refunds. Cash tips are already excluded from payouts. Bank returns
  # (ledger reversals) net back out. Payments to a corporation are still
  # included here; the caller decides based on the recipient's W-9 classification
  # whether to actually issue a 1099 to them.
  class YearEarnings
    # Payout contribution labels that are NOT compensation.
    REIMBURSEMENT_LABELS = [ "Reimbursement" ].freeze

    Result = Struct.new(:person_id, :paid_cents, :reimbursement_cents, :onchain_cents, :offline_cents, :onchain_return_cents, keyword_init: true) do
      def net_cents
        paid_cents
      end
    end

    def self.for(organization, tax_year)
      new(organization, tax_year).call
    end

    def initialize(organization, tax_year)
      @organization = organization
      @tax_year = tax_year.to_i
    end

    # { person_id => Result }
    def call
      results = Hash.new { |h, id| h[id] = Result.new(person_id: id, paid_cents: 0, reimbursement_cents: 0, onchain_cents: 0, offline_cents: 0, onchain_return_cents: 0) }

      each_onchain_payment do |person_id, reportable_cents, reimbursement_cents|
        r = results[person_id]
        r.paid_cents += reportable_cents
        r.onchain_cents += reportable_cents
        r.reimbursement_cents += reimbursement_cents
      end

      each_onchain_reversal do |person_id, reportable_cents, reimbursement_cents|
        r = results[person_id]
        r.paid_cents -= reportable_cents
        r.onchain_return_cents += reportable_cents
        r.reimbursement_cents -= reimbursement_cents
      end

      each_offline_payment do |person_id, reportable_cents, reimbursement_cents|
        r = results[person_id]
        r.paid_cents += reportable_cents
        r.offline_cents += reportable_cents
        r.reimbursement_cents += reimbursement_cents
      end

      results
    end

    private

    # Payments through CocoScout pay runs. One `payout` ledger entry per item;
    # its contributions itemize what it was for. Reimbursement components are
    # peeled off so they're not on the 1099.
    def each_onchain_payment
      entries = PayoutLedgerEntry.where(organization: @organization, category: "staffing", entry_type: "payout", payee_type: "Person")
                                 .where(occurred_at: year_range)
      entries.find_each do |entry|
        item = entry.source
        next unless item.is_a?(PayoutBatchItem)

        reimbursement, reportable = split_item(item)
        # Guard against a hand-edited ledger entry whose amount doesn't match
        # the underlying item (should never happen): scale.
        gross = reimbursement + reportable
        next if gross.zero?

        actual = -entry.amount_cents # payout entries are negative
        scale = actual.to_f / gross
        yield entry.payee_id, (reportable * scale).round, (reimbursement * scale).round
      end
    end

    # A payout that reached the payee's bank and was rejected — same split,
    # taken back out of the year.
    def each_onchain_reversal
      entries = PayoutLedgerEntry.where(organization: @organization, category: "staffing", entry_type: "reversal", payee_type: "Person")
                                 .where(occurred_at: year_range)
      entries.find_each do |entry|
        item = entry.source
        next unless item.is_a?(PayoutBatchItem)

        reimbursement, reportable = split_item(item)
        gross = reimbursement + reportable
        next if gross.zero?

        scale = entry.amount_cents.to_f / gross
        yield entry.payee_id, (reportable * scale).round, (reimbursement * scale).round
      end
    end

    # Hours the manager marked as already paid outside CocoScout. Wages minus
    # any reimbursement recorded on the entry. When no explicit amount was
    # recorded, price the hours at the member's rate for the entry's role.
    def each_offline_payment
      entries = StaffTimeEntry.where(organization: @organization, offline_paid_at: year_range).where.not(offline_paid_at: nil)
                              .includes(:house_role, shift_assignment: { shift: :house_role })
      members_by_person = @organization.organization_staff_members.where(person_id: entries.map(&:person_id).uniq)
                                       .includes(staff_role_qualifications: :house_role).index_by(&:person_id)
      entries.each do |entry|
        reimbursement = entry.offline_reimbursement_cents.to_i
        wages = if entry.offline_amount_cents.present?
          entry.offline_amount_cents.to_i
        else
          member = members_by_person[entry.person_id]
          member ? member.amount_cents_for(entry.effective_house_role, hours: entry.hours) : 0
        end
        next if wages.zero? && reimbursement.zero?

        yield entry.person_id, wages, reimbursement
      end
    end

    # Sum the payable contributions on a paid batch item, split into
    # reimbursement (not on 1099) and everything else. Excluded contributions
    # (cash tips) are already ignored.
    # Only the item's staff lines: since the runs merged, one item can also
    # carry a person's show pay, which posts to the performer ledger and isn't
    # part of this staffing payout entry.
    def split_item(item)
      reimbursement = 0
      reportable = 0
      item.payout_contributions.payable.where(category: "staffing").each do |c|
        if REIMBURSEMENT_LABELS.include?(c.label)
          reimbursement += c.amount_cents
        else
          reportable += c.amount_cents
        end
      end
      [ reimbursement, reportable ]
    end

    def year_range
      Time.zone.local(@tax_year, 1, 1).beginning_of_day..Time.zone.local(@tax_year, 12, 31).end_of_day
    end
  end
end
