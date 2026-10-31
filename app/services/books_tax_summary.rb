# frozen_string_literal: true

require "csv"

# One year of taxes, summarized (Books V1.3, plan F): the lines a Schedule C
# asks for, grouped the way a 990-EZ asks when the organization is a
# nonprofit; sales tax collected, paid and still set aside; the 1099s
# issued; what CocoScout was paid. Nothing is filed from here.
class BooksTaxSummary
  Line = Data.define(:label, :cents, :note) do
    def initialize(label:, cents:, note: nil) = super
  end

  # Schedule C lines, each from the accounts that feed it.
  SPENDING_LINES = [
    [ "Contract labor", %w[performer_pay instructor_pay contractor_pay], "Performers, instructors and contractors (1099 total beside it)" ],
    [ "Wages", %w[staff_pay], "Staff pay" ],
    [ "Rent", %w[venue], "Venue and space" ],
    [ "Advertising", %w[marketing], nil ],
    [ "Supplies", %w[supplies production_costs equipment], "Sets, costumes, props, supplies, equipment" ],
    [ "Licenses and rights", %w[licensing], nil ],
    [ "Insurance", %w[insurance], nil ],
    [ "Travel and meals", %w[travel food_and_drink], nil ],
    [ "Software and subscriptions", %w[software], "CocoScout and other software" ],
    [ "Fees", %w[ticketing_fees fees_paid_by_buyers course_fees], "Ticketing, card and platform fees, less what buyers paid" ]
  ].freeze
  NONPROFIT_INCOME_GROUPS = [
    [ "Contributions, gifts and grants", %w[sponsorship_income donation_income grant_income] ],
    [ "Program service revenue", %w[ticket_income product_income unused_pass_income course_income contract_income] ],
    [ "Sales of inventory", %w[bar_income merchandise_income] ]
  ].freeze

  def initialize(organization, year:, basis: :cash)
    @organization = organization
    @year = year.to_i
    @basis = basis.to_s == "accrual" ? :accrual : :cash
    @range = Date.new(@year, 1, 1)..Date.new(@year, 12, 31)
  end

  attr_reader :year, :basis, :range

  def nonprofit? = @organization.books_nonprofit

  def sums
    @sums ||= begin
      lines = BooksReport.new(@organization, basis: @basis).dated_lines(@range).joins(:ledger_account)
      by_key = lines.group("COALESCE(ledger_accounts.key, ledger_accounts.code)").sum(:amount_cents)
      names = @organization.ledger_accounts.pluck(:key, :code, :name, :account_type).to_h { |k, c, n, t| [ k || c, [ n, t ] ] }
      { by_key: by_key, names: names }
    end
  end

  # Gross receipts by kind of income (income is credit-normal: negate).
  def income_lines
    sums[:by_key].filter_map do |key, cents|
      name, type = sums[:names][key]
      next unless type == "income" && cents.nonzero?

      Line.new(label: name, cents: -cents)
    end.sort_by { |l| -l.cents }
  end

  def income_total_cents = income_lines.sum(&:cents)

  # The 990-EZ grouping: contributions, program service revenue, sales.
  def nonprofit_income_groups
    NONPROFIT_INCOME_GROUPS.map do |label, keys|
      cents = keys.sum { |k| -sums[:by_key][k].to_i }
      Line.new(label: label, cents: cents)
    end + [ Line.new(label: "Other revenue", cents: income_total_cents - NONPROFIT_INCOME_GROUPS.sum { |_, keys| keys.sum { |k| -sums[:by_key][k].to_i } }) ]
  end

  def spending_lines
    listed = SPENDING_LINES.flat_map { |_, keys, _| keys }
    rows = SPENDING_LINES.map { |label, keys, note| Line.new(label: label, cents: keys.sum { |k| sums[:by_key][k].to_i }, note: note) }
    other = sums[:by_key].sum { |key, cents| (sums[:names][key]&.last == "expense" && !listed.include?(key)) ? cents : 0 }
    rows << Line.new(label: "Other expenses", cents: other, note: "Everything else, including your own categories")
    rows
  end

  def spending_total_cents = spending_lines.sum(&:cents)
  def net_cents = income_total_cents - spending_total_cents

  def sales_tax
    @sales_tax ||= begin
      report = TicketTaxReport.new(@organization, from: @range.begin, to: @range.end, basis: "sale", kind: "all")
      paid = @organization.sales_tax_remittances.where(paid_on: @range).sum(:amount_cents)
      outside = OutsideTicketTax.rows(@organization, from: @range.begin, to: @range.end).sum(&:tax_cents)
      { collected_cents: report.rows.sum(&:collected_cents), refunded_cents: report.rows.sum(&:refunded_cents), net_cents: report.total_net_cents,
        outside_cents: outside, paid_cents: paid, set_aside_cents: SalesTaxSetAside.cents(@organization), rows: report.rows }
    end
  end

  def forms_1099
    @forms_1099 ||= begin
      forms = @organization.tax_form_1099s.for_year(@year).not_void.to_a
      { count: forms.size, total_cents: forms.sum(&:reported_box1_cents), filed: forms.count { |f| f.filed_at.present? }, delivered: forms.count { |f| f.status.in?(%w[delivered filed]) },
        threshold_cents: TaxForm1099.threshold_cents(@year) }
    end
  end

  def cocoscout_paid_cents
    JournalLine.where(organization_id: @organization.id).joins(:journal_entry, :ledger_account)
               .where(journal_entries: { source_type: "BillingInvoice", kind: "cocoscout_bill" }).where(ledger_accounts: { account_type: "expense" })
               .where(journal_entries: { entry_date: @range }).sum(:amount_cents)
  end

  def to_csv
    CSV.generate do |csv|
      csv << [ "#{@organization.name}: taxes #{@year}", (@basis == :cash ? "Counted when the money moved" : "Counted when it was earned") ]
      csv << []
      csv << [ nonprofit? ? "Support and revenue" : "Gross receipts" ]
      (nonprofit? ? nonprofit_income_groups : income_lines).each { |l| csv << [ l.label, dollars(l.cents) ] }
      csv << [ "Total", dollars(income_total_cents) ]
      csv << []
      csv << [ "Expenses" ]
      spending_lines.each { |l| csv << [ l.label, dollars(l.cents), l.note ] }
      csv << [ "Total", dollars(spending_total_cents) ]
      csv << [ nonprofit? ? "Change in net assets" : "Net profit", dollars(net_cents) ]
      csv << []
      csv << [ "Sales tax collected", dollars(sales_tax[:collected_cents]) ]
      csv << [ "Sales tax given back on refunds", dollars(sales_tax[:refunded_cents]) ]
      csv << [ "Tax owed on tickets other sites sold", dollars(sales_tax[:outside_cents]) ]
      csv << [ "Sales tax paid to the government", dollars(sales_tax[:paid_cents]) ]
      csv << [ "Sales tax still set aside", dollars(sales_tax[:set_aside_cents]) ]
      csv << []
      csv << [ "1099s issued", forms_1099[:count], dollars(forms_1099[:total_cents]) ]
      csv << [ "Paid to CocoScout", dollars(cocoscout_paid_cents) ]
    end
  end

  private

  def dollars(cents) = format("%.2f", cents / 100.0)
end
