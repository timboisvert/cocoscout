# frozen_string_literal: true

# Fold standalone service payments into the payment they belong to, on every
# contract that already has them.
#
# bill_services! used to give each service they pay us for its own
# ContractPayment beside the event's payment — "$350 rent" and "$50 booth tech"
# as two invoices for one night. Now a service folds into that payment
# (Contract#bill_services!). This does the same for rows that were already
# generated the old way: every pending, uncommitted, direct service row with a
# pending direct payment of the deal on the same show/date (or, for a
# once-per-contract service, the last such payment) is folded in and the row
# removed. Paid rows, rows in a payout run, rows that really do net against a
# payout, and rows with nothing to fold into are left alone. Idempotent.
class ServicePaymentFoldBackfill
  Result = Struct.new(:contracts_touched, :folded, :left_alone, :log, keyword_init: true)

  def self.run(dry_run: false, contract_ids: nil)
    new(dry_run: dry_run, contract_ids: contract_ids).run
  end

  def initialize(dry_run:, contract_ids: nil)
    @dry_run = dry_run
    @contract_ids = contract_ids
  end

  def run
    result = Result.new(contracts_touched: 0, folded: 0, left_alone: 0, log: [])
    scope = Contract.includes(:contract_payments)
    scope = scope.where(id: @contract_ids) if @contract_ids.present?

    scope.find_each do |contract|
      services = contract.draft_services
      next if services.blank?

      touched = false
      contract.contract_payments.status_pending.by_due_date.to_a.each do |row|
        next unless contract.service_charge?(row)
        # A "deduct from payout" row on a deal that never pays them anything is
        # a direct charge in all but name (ContractPayment#deduct_from_payout?
        # already says so) — it folds too. A real deduction stays put.
        next if row.in_payout_run? || row.deduct_from_payout? || row.includes_services?

        service = services.detect { |s| row.description == s["name"] || row.description.to_s.start_with?("#{s['name']} — ") }
        per_event = row.description != service["name"]
        host = contract.service_host_payment(direction: row.direction, settlement: "direct",
                                             date: (per_event ? row.due_date : nil), show_id: row.show_id)
        if host.nil? || host.id == row.id
          result.left_alone += 1
          result.log << "contract ##{contract.id}: kept '#{row.description}' $#{row.amount} — nothing to fold into"
          next
        end

        result.log << "contract ##{contract.id}: fold '#{row.description}' $#{row.amount} into '#{host.description}' " \
                      "$#{host.amount} → $#{(host.amount.to_f + row.amount.to_f).round(2)}"
        unless @dry_run
          ContractPayment.transaction do
            host.fold_service!(name: service["name"], amount: row.amount, billed_for: (per_event ? row.due_date : nil))
            row.destroy!
          end
        end
        result.folded += 1
        touched = true
      end
      result.contracts_touched += 1 if touched
    end

    result
  end
end
