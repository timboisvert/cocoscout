# frozen_string_literal: true

require "rails_helper"

# My Payments, rebuilt (Tim, 2026-10-10): what's coming, by where it stands,
# line by line, with anything taken out of a share listed under it; past
# payments each say what they were for. No list of everything ever earned
# minus "Already paid out". In the payee's words since 2026-10-15: on its way,
# still to be paid (approved, waiting for approval), deposited; nothing says
# paid until the payout provider says deposited.
RSpec.describe "My Payments", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) do
    create(:person, user: user, stripe_account_id: "acct_me", payouts_enabled: true).tap { |p| user.update!(default_person: p) }
  end
  let(:org) { create(:organization, :pro, name: "Stars & Garters") }
  let(:production) { create(:production, organization: org, production_type: "third_party", name: "Inevitable") }
  let(:contractor) { create(:contractor, organization: org, person: person, name: "Dan's Magic") }
  let(:contract) do
    create(:contract, :active, organization: org, production: production, contractor: contractor, contractor_name: contractor.name)
  end

  before { post handle_signin_path, params: { email_address: user.email_address, password: password } }

  def charge!(description, amount, due)
    create(:contract_payment, contract: contract, direction: "incoming", description: description, amount: amount,
                              settlement_method: "payout_deduction", due_date: due)
  end

  def text(body) = body.gsub(/\s+/, " ")

  describe "a share with a charge taken out" do
    let!(:share) do
      create(:contract_payment, :outgoing, contract: contract, description: "Aug 9 — 50% to them", amount: 257.50,
                                           due_date: Date.new(2026, 8, 9))
    end
    let!(:booth) { charge!("Booth Tech — Aug 9, 2026", 50, Date.new(2026, 8, 9)) }
    let!(:item) do
      ContractorPayoutRunService.add_contract_payment!(share)
      PayoutBatchItem.find_by!(payee: person)
    end

    it "shows the run's lines under Still to be paid, the charge under its share" do
      get my_payments_path
      html = text(response.body)

      expect(html).to match(/Still to be paid<\/div> <div[^>]*>\$207\.50/)
      expect(html).to include("Approved", "Goes out")
      expect(html).to include("Dan&#39;s Magic — Aug 9 — your 50% share", "$257.50", "Booth Tech — Aug 9, 2026", "−$50.00")
      expect(html).to match(/You get<\/span> <span[^>]*>\$207\.50/)
      expect(html).not_to include("to them")
      expect(html).not_to include("Already paid out")
    end

    it "is on its way once sent, and a past payment once the bank deposit is confirmed, saying what it was for" do
      item.mark_paid!(transfer_id: "tr_me")

      get my_payments_path
      html = text(response.body)
      expect(html).to include("Nothing waiting right now")
      expect(html).to match(/On its way<\/div> <div[^>]*>\$207\.50/)
      expect(html).to include("expected about", "Dan&#39;s Magic — Aug 9 — your 50% share", "Booth Tech — Aug 9, 2026")
      expect(html).to match(/Sent to you in #{Date.current.year}<\/span> <span[^>]*>\$207\.50/)
      expect(html).to include("No payments yet.") # on its way, so not a past payment yet

      get my_payment_receipt_path(kind: "run", id: item.id)
      html = text(response.body)
      expect(html).to include("On its way", "Taken out of your share", "Booth Tech — Aug 9, 2026", "−$50.00")
      expect(html).to match(/You got<\/span> <span[^>]*>\$207\.50/)
      expect(html).to match(/Sent to your bank<\/span> <span[^>]*>\$207\.50/)

      item.update!(deposited_at: Time.current)
      get my_payments_path
      html = text(response.body)
      expect(html).to match(/On its way<\/div> <div[^>]*>\$0\.00/)
      expect(html).to include(Time.current.strftime("%B %Y"), "Deposited #{Time.current.strftime('%a, %b %-d')}")

      get my_payment_receipt_path(kind: "run", id: item.id)
      expect(text(response.body)).to match(/Deposited to your bank<\/span> <span[^>]*>\$207\.50/)
    end
  end

  it "lists a show payout that's worked out but not in a run yet, and nets an advance" do
    show_production = create(:production, organization: org, name: "Bright Star Circus")
    show = create(:show, production: show_production, date_and_time: Time.zone.local(2026, 10, 3, 19))
    payout = ShowPayout.create!(show: show, status: "awaiting_payout", calculated_at: Time.current, total_payout: 50)
    ShowPayoutLineItem.create!(show_payout: payout, payee: person, amount: 50).sync_earning_ledger_entry!
    PayoutLedgerEntry.create!(organization: org, payee: person, entry_type: "advance", category: "performer",
                              amount_cents: -2_000, occurred_at: Time.current)

    get my_payments_path
    html = text(response.body)
    expect(html).to include("Approved", "Goes out once it&#39;s added to a payout run", "Bright Star Circus", "October 3, 2026", "$50.00")
    expect(html).to include("Advances to repay", "−$20.00")
    expect(html).to match(/Still to be paid<\/div> <div[^>]*>\$30\.00/)
  end

  describe "a share that went wholly toward what they owed" do
    let!(:share) do
      create(:contract_payment, :outgoing, contract: contract, description: "Oct 8 — 40% to them", amount: 18,
                                           due_date: Date.new(2026, 10, 8))
    end

    before do
      charge!("Rehearsal balance — Aug 26, 2026", 6, Date.new(2026, 8, 26))
      charge!("Rehearsal — Sep 6, 2026", 60, Date.new(2026, 9, 6))
      charge!("Rehearsal — Sep 13, 2026", 60, Date.new(2026, 9, 13))
      ContractorPayoutRunService.add_contract_payment!(share)
    end

    it "lists it as settled with what it paid down, and a receipt of what's still to come out" do
      expect(share.reload.payment_method).to eq("offset")

      get my_payments_path
      html = text(response.body)
      expect(html).to include("Dan&#39;s Magic — Oct 8 — your 40% share", "$18.00", "went toward what you owe")
      expect(html).to include("Rehearsal balance — Aug 26, 2026", "−$6.00", "Rehearsal — Sep 6, 2026", "−$12.00")
      expect(html).to match(/Sent to you in #{Date.current.year}<\/span> <span[^>]*>\$0\.00/)

      get my_payment_receipt_path(kind: "offset", id: share.id)
      html = text(response.body)
      expect(html).to include("Your share: Oct 8 — 40% to them", "Went toward what you owe")
      expect(html).to include("Still to come out of your next share", "Rehearsal balance — Sep 6, 2026", "$48.00", "Rehearsal — Sep 13, 2026", "$60.00")
      expect(html).to match(/Deposited to your bank<\/span> <span[^>]*>\$0\.00/)
    end

    it "never shows someone else's" do
      stranger = create(:user, password: password)
      create(:person, user: stranger).tap { |p| stranger.update!(default_person: p) }
      post handle_signin_path, params: { email_address: stranger.email_address, password: password }

      get my_payment_receipt_path(kind: "offset", id: share.id)
      expect(response).to redirect_to(my_payments_path)
    end
  end
end
