# frozen_string_literal: true

# The accounts every organization's books start with. Keys are what the code
# posts to; names are what a theater would read if it ever opens its books —
# plain words ("Money owed to you"), never "A/R".
#
# Accounts are created on first use (ensure!), so existing orgs need no
# backfill and an org that never touches money never gets a chart.
class ChartOfAccounts
  SYSTEM = {
    bank: { code: "1000", name: "Bank", type: "asset" },
    cocoscout_balance: { code: "1010", name: "CocoScout balance", type: "asset" },
    door_cash: { code: "1020", name: "Door cash", type: "asset" },
    owed_to_you: { code: "1100", name: "Money owed to you", type: "asset" },
    advances: { code: "1200", name: "Advances to performers", type: "asset" },
    you_owe: { code: "2000", name: "Money you owe", type: "liability" },
    credit_card: { code: "2010", name: "Credit card", type: "liability" },
    owed_to_payees: { code: "2100", name: "Owed to performers and staff", type: "liability" },
    tips_owed: { code: "2110", name: "Tips owed to staff", type: "liability" },
    advance_ticket_sales: { code: "2200", name: "Tickets sold for upcoming shows", type: "liability" },
    advance_product_sales: { code: "2210", name: "Products sold for upcoming shows", type: "liability" },
    pass_credits_unused: { code: "2220", name: "Pass credits not yet used", type: "liability" },
    # What gift certificates paid for tickets; their sale isn't recorded here
    # yet (issued by hand, V1.3's Books will), so this runs negative until then.
    gift_certificates_outstanding: { code: "2230", name: "Gift certificates outstanding", type: "liability" },
    tax_to_remit: { code: "2300", name: "Tax to pay the government", type: "liability" },
    owner_equity: { code: "3000", name: "Owner's equity", type: "equity" },
    retained_earnings: { code: "3100", name: "Retained earnings", type: "equity" },
    ticket_income: { code: "4000", name: "Ticket income", type: "income" },
    product_income: { code: "4010", name: "Product income", type: "income" },
    unused_pass_income: { code: "4020", name: "Unused pass credits", type: "income" },
    contract_income: { code: "4100", name: "Rental and contract income", type: "income" },
    course_income: { code: "4200", name: "Course income", type: "income" },
    sponsorship_income: { code: "4300", name: "Sponsorship", type: "income" },
    donation_income: { code: "4310", name: "Donations", type: "income" },
    grant_income: { code: "4320", name: "Grants", type: "income" },
    bar_income: { code: "4400", name: "Bar and concessions", type: "income" },
    merchandise_income: { code: "4410", name: "Merchandise", type: "income" },
    other_income: { code: "4900", name: "Other income", type: "income" },
    performer_pay: { code: "5000", name: "Performer pay", type: "expense" },
    instructor_pay: { code: "5050", name: "Instructor pay", type: "expense" },
    contractor_pay: { code: "5060", name: "Paid to contractors", type: "expense" },
    staff_pay: { code: "5100", name: "Staff pay", type: "expense" },
    venue: { code: "5200", name: "Venue", type: "expense" },
    production_costs: { code: "5300", name: "Production", type: "expense" },
    marketing: { code: "5400", name: "Marketing", type: "expense" },
    supplies: { code: "5310", name: "Supplies", type: "expense" },
    travel: { code: "5320", name: "Travel", type: "expense" },
    food_and_drink: { code: "5330", name: "Food and drink", type: "expense" },
    licensing: { code: "5340", name: "Licensing and rights", type: "expense" },
    insurance: { code: "5350", name: "Insurance", type: "expense" },
    equipment: { code: "5500", name: "Tech and equipment", type: "expense" },
    ticketing_fees: { code: "5600", name: "Ticketing and card fees", type: "expense" },
    # Buyer-paid fees offset the fees line, so passing fees on nets to zero.
    fees_paid_by_buyers: { code: "5610", name: "Fees paid by buyers", type: "expense", subtype: "contra" },
    course_fees: { code: "5630", name: "Course platform and card fees", type: "expense" },
    software: { code: "5700", name: "Software and subscriptions", type: "expense" },
    other_expenses: { code: "5900", name: "Other expenses", type: "expense" }
  }.freeze

  # Create whichever system accounts the org doesn't have yet. Idempotent and
  # race-safe (the unique index settles concurrent first posts).
  def self.ensure!(organization)
    existing = organization.ledger_accounts.where.not(key: nil).pluck(:key)
    missing = SYSTEM.keys.map(&:to_s) - existing
    return if missing.empty?

    now = Time.current
    rows = missing.map do |key|
      spec = SYSTEM.fetch(key.to_sym)
      { organization_id: organization.id, key: key, code: spec[:code], name: spec[:name],
        account_type: spec[:type], subtype: spec[:subtype], system: true, active: true,
        created_at: now, updated_at: now }
    end
    LedgerAccount.insert_all(rows, unique_by: %i[organization_id code])
  end

  # A system account's name follows this list: when one is renamed here
  # ("Equipment" became "Tech and equipment"), the rows catch up.
  def self.rename!(organization)
    organization.ledger_accounts.where(system: true).where.not(key: nil).find_each do |account|
      spec = SYSTEM[account.key.to_sym]
      account.update_column(:name, spec[:name]) if spec && account.name != spec[:name]
    end
  end

  # The org's account for a system key, creating the chart on first use.
  def self.account(organization, key)
    key = key.to_s
    raise ArgumentError, "unknown account #{key}" unless SYSTEM.key?(key.to_sym)

    organization.ledger_accounts.find_by(key: key) || begin
      ensure!(organization)
      organization.ledger_accounts.find_by!(key: key)
    end
  end
end
