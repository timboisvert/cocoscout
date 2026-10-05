# frozen_string_literal: true

# Books stage B, the money that never passes through CocoScout: what a show
# took in elsewhere (Ticket Tailor, Eventbrite, the bar), what it cost, and a
# production's spread expenses. All of it is typed into Show Financials or
# the production's expenses, so the books post from those records and
# restate whenever they change.
#
#   Ticket sales lines from other sources, when the theater sells — income
#                       the theater is owed (Money owed to you / Ticket income)
#   Other revenue       — likewise, less the "CocoScout products" line
#                       ticketing writes itself (Money owed to you / Other income)
#   Expenses            — paid from the bank, by category
#   Flat fee            — a show played for a fee with no contract behind it
#                       (Money owed to you / Rental and contract income)
#   ProductionExpense   — a cost spread over shows, posted once on its date
#   ContractPayment     — contract money that moved outside CocoScout: a check
#                       or cash received (Bank / Rental and contract income),
#                       or a contractor paid by hand or by offset (Contractor
#                       pay / Bank). One collected online, deducted on a run or
#                       paid through a run already posts from its ledger row.
class BooksOutsidePoster
  CATEGORY_ACCOUNTS = { "venue" => :venue, "production" => :production_costs, "marketing" => :marketing,
                        "talent" => :performer_pay, "other" => :other_expenses }.freeze
  KINDS = %w[outside_tickets other_revenue flat_fee expenses].freeze

  def self.post_financials!(financials)
    # A line's callback can fire while its financials row is being destroyed.
    return remove_financials!(financials) if financials.destroyed?

    show = financials.show
    organization = show.production.organization
    date = show.date_and_time.to_date
    dims = { show: show, production: show.production }

    tickets = outside_ticket_cents(financials, show)
    LedgerPosting.post!(organization: organization, source: financials, kind: "outside_tickets", entry_date: date, cash_date: date,
                        memo: "Ticket sales elsewhere · #{show.display_name}",
                        lines: tickets.zero? ? [] : [ { account: :owed_to_you, amount_cents: tickets, **dims }, { account: :ticket_income, amount_cents: -tickets, **dims } ])

    other = other_revenue_cents(financials)
    LedgerPosting.post!(organization: organization, source: financials, kind: "other_revenue", entry_date: date, cash_date: date,
                        memo: "Other revenue · #{show.display_name}",
                        lines: other.zero? ? [] : [ { account: :owed_to_you, amount_cents: other, **dims }, { account: :other_income, amount_cents: -other, **dims } ])

    fee = flat_fee_cents(financials, show)
    LedgerPosting.post!(organization: organization, source: financials, kind: "flat_fee", entry_date: date, cash_date: date,
                        memo: "Flat fee · #{show.display_name}",
                        lines: fee.zero? ? [] : [ { account: :owed_to_you, amount_cents: fee, **dims }, { account: :contract_income, amount_cents: -fee, **dims } ])

    by_category = expense_cents(financials)
    total = by_category.values.sum
    lines = by_category.map { |account, cents| { account: account, amount_cents: cents, **dims } }
    lines << { account: :bank, amount_cents: -total } if total.positive?
    LedgerPosting.post!(organization: organization, source: financials, kind: "expenses", entry_date: date, cash_date: date,
                        memo: "Expenses · #{show.display_name}", lines: total.zero? ? [] : lines)
  rescue StandardError => e
    raise if Rails.env.test?

    Rails.logger.error("[BooksOutsidePoster] financials #{financials.id}: #{e.class}: #{e.message}")
  end

  def self.remove_financials!(financials)
    KINDS.each { |kind| LedgerPosting.unpost!(source: financials, kind: kind) }
  end

  def self.post_production_expense!(expense)
    production = expense.production
    date = expense.purchase_date || expense.created_at.to_date
    cents = (expense.total_amount.to_f * 100).round
    lines = expense.active && cents.positive? ? [ { account: CATEGORY_ACCOUNTS.fetch(expense.category.to_s, :other_expenses), amount_cents: cents, production: production },
                                                   { account: :bank, amount_cents: -cents } ] : []
    LedgerPosting.post!(organization: production.organization, source: expense, kind: "production_expense", entry_date: date, cash_date: date,
                        memo: "#{expense.name} · #{production.name}", lines: lines)
  rescue StandardError => e
    raise if Rails.env.test?

    Rails.logger.error("[BooksOutsidePoster] production expense #{expense.id}: #{e.class}: #{e.message}")
  end

  def self.remove_production_expense!(expense)
    LedgerPosting.unpost!(source: expense, kind: "production_expense")
  end

  # Contract money that never touched CocoScout's rail. Idempotent, and
  # withdrawn again when the payment goes back to unpaid.
  def self.post_contract_payment!(payment)
    return remove_contract_payment!(payment) if payment.destroyed?

    contract = payment.contract
    cents = payment.amount_cents
    lines = []
    if payment.status_paid? && cents.positive? && !on_the_rail?(payment)
      dims = { show: payment.show, production: payment.show&.production || contract.production }.compact
      lines = if payment.direction_incoming?
        [ { account: :bank, amount_cents: cents }, { account: :contract_income, amount_cents: -cents, **dims } ]
      else
        [ { account: :contractor_pay, amount_cents: cents, **dims }, { account: :bank, amount_cents: -cents } ]
      end
    end
    date = payment.paid_date || payment.updated_at.to_date
    LedgerPosting.post!(organization: contract.organization, source: payment, kind: "contract_payment", entry_date: date, cash_date: date,
                        memo: [ payment.description.presence || "Contract payment", contract.contractor&.name ].compact.join(" · "), lines: lines)
  rescue StandardError => e
    raise if Rails.env.test?

    Rails.logger.error("[BooksOutsidePoster] contract payment #{payment.id}: #{e.class}: #{e.message}")
  end

  def self.remove_contract_payment!(payment)
    LedgerPosting.unpost!(source: payment, kind: "contract_payment")
  end

  # Already on the books through a ledger row: collected online (the cash
  # ledger), or riding a payout run as a share or a deduction (the payout
  # ledger). A full wash leaves no run line behind, so both its sides post
  # here and cancel out in the bank.
  def self.on_the_rail?(payment)
    payment.stripe_checkout_session_id.present? ||
      OrgCashEntry.exists?(source: payment) ||
      PayoutContribution.exists?(source: payment) ||
      PayoutLedgerEntry.exists?(source: payment)
  end

  # Ticket money taken elsewhere is the theater's only when it sells the
  # tickets (a contractor who sells reports their own sales and owes a share,
  # which is contract income). A flat-fee show's tickets aren't the theater's.
  # Financials typed before sources existed have no lines, only the total.
  def self.outside_ticket_cents(financials, show)
    return 0 unless financials.ticket_sales?
    return 0 unless org_sells?(show)

    lines = financials.ticket_sales_lines.includes(:ticket_source).to_a
    return (financials.ticket_revenue.to_f * 100).round if lines.empty?

    lines.reject { |line| line.ticket_source&.built_in? }.sum { |line| (line.amount.to_f * 100).round }
  end

  def self.contract_for(show)
    show.ticket_listing&.contract || show.space_rental&.contract || show.production.contract
  end

  def self.org_sells?(show)
    contract = contract_for(show)
    contract.nil? || contract.org_sells_tickets?
  end

  # A flat fee under a contract arrives as that contract's payments; without
  # one, the financials are the only record of it.
  def self.flat_fee_cents(financials, show)
    return 0 unless financials.flat_fee?
    return 0 if contract_for(show)

    (financials.flat_fee.to_f * 100).round
  end

  def self.other_revenue_cents(financials)
    financials.normalized_other_revenue_details
              .select { |item| item.is_a?(Hash) && item["description"] != TicketSalesSync::PRODUCTS_LABEL }
              .sum { |item| (item["amount"].to_f * 100).round }
  end

  # By category: the expense items when there are any, else the legacy
  # details, else the one typed total.
  def self.expense_cents(financials)
    rows = if financials.expense_items.any?
      financials.expense_items.map { |item| [ item.category, item.amount ] }
    elsif financials.normalized_expense_details.any?
      financials.normalized_expense_details.select { |item| item.is_a?(Hash) }.map { |item| [ item["category"], item["amount"] ] }
    else
      [ [ "other", financials.expenses ] ]
    end
    rows.each_with_object(Hash.new(0)) do |(category, amount), sums|
      cents = (amount.to_f * 100).round
      sums[CATEGORY_ACCOUNTS.fetch(category.to_s, :other_expenses)] += cents if cents.positive?
    end
  end

  private_class_method :on_the_rail?, :outside_ticket_cents, :contract_for, :org_sells?, :flat_fee_cents, :other_revenue_cents, :expense_cents
end
