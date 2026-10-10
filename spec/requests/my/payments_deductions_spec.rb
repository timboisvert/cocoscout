# frozen_string_literal: true

require "rails_helper"

# Tim, 2026-10-10: when a share has something taken out of it (a rehearsal,
# a service they owed), My Payments shows the working: the share, what came
# out, what they get. A share that went wholly toward what they owed shows
# too, though nothing was deposited.
RSpec.describe "My Payments: what came out of a share", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) do
    create(:person, user: user, stripe_account_id: "acct_me", payouts_enabled: true).tap { |p| user.update!(default_person: p) }
  end
  let(:org) { create(:organization, :pro, name: "Stars & Garters") }
  let(:production) { create(:production, organization: org, production_type: "third_party", name: "Improvised Animorphs") }
  let(:contractor) { create(:contractor, organization: org, person: person, name: "Animorphs Co") }
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

    it "lists the charge under the share while it's owed and on its way" do
      expect(item.amount_cents).to eq(20_750)

      get my_payments_path
      html = text(response.body)

      expect(html).to include("Taken out of your share", "Booth Tech — Aug 9, 2026", "−$50.00")
      expect(html).to match(/You get<\/span> <span[^>]*>\$207\.50/)
      # A deduction isn't a payout already made.
      expect(html).not_to include("Already paid out")
      expect(html).to include("Your share $257.50, less $50.00 taken out for what you owe")
    end

    it "shows the working on the deposit and its receipt" do
      item.mark_paid!(transfer_id: "tr_me")

      get my_payments_path
      expect(text(response.body)).to include("after $50.00 taken out")

      get my_payment_receipt_path(kind: "run", id: item.id)
      html = text(response.body)
      expect(html).to include("Taken out of your share", "Booth Tech — Aug 9, 2026", "−$50.00")
      expect(html).to match(/You got<\/span> <span[^>]*>\$207\.50/)
      expect(html).to match(/Deposited to your bank<\/span> <span[^>]*>\$207\.50/)
    end
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

    it "lists it as settled, with a receipt of what it paid down and what's still to come out" do
      expect(share.reload.payment_method).to eq("offset")

      get my_payments_path
      html = text(response.body)
      expect(html).to include("Oct 8 — 40% to them", "$18.00", "went toward what you owe")
      expect(html).to match(/Total received<\/div> <div[^>]*>\$0\.00/)

      get my_payment_receipt_path(kind: "offset", id: share.id)
      html = text(response.body)
      expect(html).to include("Your share: Oct 8 — 40% to them", "Went toward what you owe")
      expect(html).to include("Rehearsal balance — Aug 26, 2026", "−$6.00", "Rehearsal — Sep 6, 2026", "−$12.00")
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
