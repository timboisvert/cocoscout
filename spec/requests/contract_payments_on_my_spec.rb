# frozen_string_literal: true

require "rails_helper"

# A contractor sees their contract's payments on My Contracts and My Payments,
# each tied to its contract and saying where it stands (Tim, 2026-11-22).
RSpec.describe "Contract payments on My Contracts and My Payments", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:production) { create(:production, organization: org, name: "Carded", production_type: "third_party") }
  let(:dan) { create(:user, password: password) }
  let!(:dan_person) { create(:person, user: dan, name: "Dan Feltey", email: dan.email_address).tap { |p| dan.update!(default_person: p) } }
  let!(:contractor) { create(:contractor, organization: org, name: "Carded LLC", email: dan.email_address, person: dan_person) }
  let!(:contract) { create(:contract, :active, organization: org, production: production, contractor: contractor, contractor_name: "Carded LLC", production_name: "Carded") }

  before do
    create(:organization_role, :manager, user: owner, organization: org)
    post handle_signin_path, params: { email_address: dan.email_address, password: password }
  end

  def payment(description, amount, due:, **attrs)
    contract.contract_payments.create!(description: description, amount: amount, direction: "outgoing", due_date: due, **attrs)
  end

  it "says where each payment stands, in words" do
    due = payment("Dec 4 show", 500, due: Date.current + 10)
    by_check = payment("Oct 2 show", 1_600, due: Date.current - 40)
    by_check.pay_offline!(method: "check", paid_on: Date.new(2026, 10, 3))
    cancelled = payment("Dropped date", 300, due: Date.current + 3, status: "cancelled")
    incoming = contract.contract_payments.create!(description: "Booth tech", amount: 150, direction: "incoming", due_date: Date.current)

    expect(due.payee_stage.words).to eq("Due #{(Date.current + 10).strftime('%b %-d')}")
    expect(by_check.payee_stage.words).to eq("Paid by check Oct 3")
    expect(by_check.payee_stage).to be_paid
    expect(cancelled.payee_stage).to be_nil
    expect(incoming.payee_stage).to be_nil
  end

  it "lists the contract's payments on My Contracts with their status and totals, leaving cancelled ones out" do
    payment("Dec 4 show", 500, due: Date.current + 10)
    payment("Oct 2 show", 1_600, due: Date.current - 40).pay_offline!(method: "check", paid_on: Date.current - 39)
    payment("Dropped date", 300, due: Date.current + 3, status: "cancelled")

    get my_contracts_path
    html = response.body.gsub(/\s+/, " ")
    expect(html).to include("data-contract-payments", "What this contract pays you", "Paid by check", "Due ", "$1,600.00", "$500.00")
    expect(html).not_to include("Dropped date")
  end

  it "puts payments not on a payout run under the contract on My Payments, and hand-paid ones in past payments and the year total" do
    payment("Dec 4 show", 500, due: Date.current + 10)
    payment("Oct 2 show", 1_600, due: Date.current - 40).pay_offline!(method: "check", paid_on: Date.current - 39)

    get my_payments_path
    html = response.body.gsub(/\s+/, " ")
    expect(html).to include("Under your contract for Carded", "With Stars &amp; Garters", "Dec 4 show", "Contract · Carded",
                            "data-contract-paid-by-hand", "Oct 2 show", "Paid")
    summary = MyPaymentsSummary.new(dan_person)
    expect(summary.contract_groups.sole.total_cents).to eq(500_00)
    expect(summary.paid_this_year_cents).to eq((Date.current - 39).year == Date.current.year ? 1_600_00 : 0)
  end
end
