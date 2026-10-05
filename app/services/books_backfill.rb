# frozen_string_literal: true

# Books stage B: every historical row of the two sub-ledgers, every show's
# financials and every production expense, posted to the books in date
# order. Idempotent (LedgerPosting restates), so it can run again after a
# posting rule changes. Dry run by default: everything is posted inside a
# transaction, the reconciliation is read, and then it's rolled back.
class BooksBackfill
  Row = Data.define(:organization, :cash_rows, :owed_rows, :financials, :expenses, :mismatches, :trial_balance_cents)
  Result = Data.define(:rows, :dry_run)

  def self.run!(dry_run: true, organization_ids: nil)
    rows = []
    ActiveRecord::Base.transaction do
      scope = organization_ids ? Organization.where(id: organization_ids) : Organization.all
      scope.order(:id).find_each { |organization| rows << post_organization!(organization) }
      raise ActiveRecord::Rollback if dry_run
    end
    Result.new(rows: rows, dry_run: dry_run)
  end

  def self.post_organization!(organization)
    cash = OrgCashEntry.where(organization: organization).order(:occurred_at, :id)
    cash.find_each { |entry| BooksPoster.post!(entry) }
    owed = PayoutLedgerEntry.where(organization: organization).order(:occurred_at, :id)
    owed.find_each { |entry| BooksPoster.post!(entry) }
    financials = ShowFinancials.joins(show: :production).where(productions: { organization_id: organization.id })
                               .includes(:expense_items, :ticket_sales_lines, show: :production)
    financials.find_each { |f| BooksOutsidePoster.post_financials!(f) }
    expenses = ProductionExpense.joins(:production).where(productions: { organization_id: organization.id })
    expenses.find_each { |e| BooksOutsidePoster.post_production_expense!(e) }
    Row.new(organization: organization, cash_rows: cash.count, owed_rows: owed.count, financials: financials.count, expenses: expenses.count,
            mismatches: BooksReconciliation.check(organization), trial_balance_cents: LedgerPosting.trial_balance(organization).values.sum)
  end
end
