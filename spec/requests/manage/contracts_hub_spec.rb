# frozen_string_literal: true

require "rails_helper"

# The Contracts hub shows what's in motion — waiting on a signature, drafts,
# anything signed lately — above the calendar, and hands the whole book off to
# All Contracts (sortable by upcoming date or by name), the way the Money hub
# hands off to All Financials.
RSpec.describe "Manage::Contracts hub and All Contracts", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, production_type: "third_party") }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  describe "the hub" do
    let!(:old_active) do
      create(:contract, :active, organization: org, production: production, contractor_name: "Old Reliable",
                                 activated_at: 4.months.ago, contract_start_date: 2.weeks.from_now)
    end
    let!(:just_signed) do
      create(:contract, :active, organization: org, production: production, contractor_name: "Fresh Ink",
                                 signing_mode: :esign, activated_at: 3.days.ago, executed_at: 3.days.ago, signing_state: :executed)
    end
    let!(:out_for_signature) do
      create(:contract, organization: org, production: production, contractor_name: "Waiting Room",
                        signing_mode: :esign, signing_state: :out_for_signature)
    end
    let!(:draft) { create(:contract, organization: org, production: production, contractor_name: "Half Baked") }

    it "lists what's in motion with its state, not the whole book, and links to All Contracts" do
      get manage_contracts_path
      expect(response).to have_http_status(:ok)

      body = response.body
      expect(body).to include("In motion")
      expect(body).to include("Waiting Room").and include("Out for signature")
      expect(body).to include("Half Baked")
      expect(body).to include("Fresh Ink").and include("Signed 3 days ago")
      # An active contract that's just ticking along isn't "in motion"
      expect(body).not_to include("Old Reliable")
      # Waiting-on-signature first, then drafts, then recently signed
      expect(body.index("Waiting Room")).to be < body.index("Half Baked")
      expect(body.index("Half Baked")).to be < body.index("Fresh Ink")

      expect(body).to include("All contracts")
      expect(body).to include(all_manage_contracts_path)
      expect(body).not_to include("Active Contracts")
    end

    it "leads with a contract that has a payment overdue, whatever month it fell in" do
      old_active.contract_payments.create!(description: "Rent", amount: 500, direction: "incoming", due_date: 3.months.ago.to_date)
      old_active.contract_payments.create!(description: "Rent", amount: 500, direction: "incoming", due_date: 2.months.ago.to_date)
      old_active.contract_payments.create!(description: "Rent", amount: 500, direction: "incoming", due_date: 1.month.from_now.to_date)

      get manage_contracts_path
      body = response.body
      # The Overdue tile carries the amount owed to us
      expect(body).to include("Overdue")
      expect(body).to include("$1,000.00")
      expect(body).to include("2 payments past due")
      expect(body).to include("Old Reliable").and include("2 payments overdue")
      expect(body.index("Old Reliable")).to be < body.index("Waiting Room")
      # The old banner is gone — the list is the warning now
      expect(body).not_to include("use the month arrows")
    end

    # A past-due payment that's already in a payout run isn't being chased. The
    # badge and the amount both have to say which money is where.
    context "when an overdue payment is already in a payout run" do
      let(:payee) { create(:person) }

      def stage_in_run!(payment, status:)
        batch = PayoutBatch.create!(organization: org, status: status, kind: "performer")
        item = batch.items.create!(payee: payee, amount_cents: (payment.amount.to_f * 100).round)
        batch.payout_contributions.create!(source: payment, payout_batch_item: item, payee: payee,
                                           amount_cents: item.amount_cents, label: "Settlement")
        batch
      end

      it "says the payment is in flight, not overdue, and shows that payment's money" do
        overdue = old_active.contract_payments.create!(description: "Settlement", amount: 400,
                                                       direction: "outgoing", due_date: 1.week.ago.to_date)
        old_active.contract_payments.create!(description: "Rent", amount: 2_600, direction: "incoming",
                                             due_date: 3.months.from_now.to_date)
        stage_in_run!(overdue, status: "funded")

        get manage_contracts_path
        body = response.body
        expect(body).to include("Old Reliable").and include("Payment in flight")
        expect(body).not_to include("Payment overdue")
        # The Value column carries the money in motion, with the contract's own
        # worth as context underneath.
        expect(body).to include("$400.00")
        expect(body).to include("of $3,000")
      end

      it "says it's in a draft run when the run hasn't gone out yet" do
        overdue = old_active.contract_payments.create!(description: "Settlement", amount: 400,
                                                       direction: "outgoing", due_date: 1.week.ago.to_date)
        stage_in_run!(overdue, status: "draft")

        get manage_contracts_path
        expect(response.body).to include("Payment in a draft payout run")
        expect(response.body).not_to include("Payment overdue")
      end

      it "still calls it overdue when the run failed" do
        overdue = old_active.contract_payments.create!(description: "Settlement", amount: 400,
                                                       direction: "outgoing", due_date: 1.week.ago.to_date)
        stage_in_run!(overdue, status: "failed")

        get manage_contracts_path
        expect(response.body).to include("Payment overdue")
      end

      it "chases the payment that isn't in a run, and counts only that one" do
        in_run = old_active.contract_payments.create!(description: "Settlement", amount: 400,
                                                      direction: "outgoing", due_date: 2.weeks.ago.to_date)
        old_active.contract_payments.create!(description: "Rent", amount: 750, direction: "incoming",
                                             due_date: 1.week.ago.to_date)
        stage_in_run!(in_run, status: "processing")

        get manage_contracts_path
        body = response.body
        expect(body).to include("Payment overdue")
        expect(body).not_to include("2 payments overdue")
        # Only the money still to chase, not the pair and not the contract.
        expect(body).to include("$750.00")
      end
    end

    it "shows an amendment waiting on a signature" do
      template = org.contract_templates.create!(name: "T", content: "<p>{{production_name}}</p>")
      old_active.update!(signing_mode: :esign, contract_template: template)
      old_active.sign_by_org!(signer_name: "Tim", signed_by: owner, request: nil)
      old_active.send_for_signature!
      old_active.execute_by_signature!(signer_name: "Q", signer_email: "q@example.com", request: double(remote_ip: "1.1.1.1", user_agent: "rspec"))
      old_active.update!(activated_at: 4.months.ago, executed_at: 4.months.ago)
      old_active.contract_versions.update_all(executed_at: 4.months.ago)
      old_active.update_amend_data("production_name" => "Renamed")
      post apply_amendments_manage_contract_path(old_active), params: { requires_signature: "1" }

      get manage_contracts_path
      expect(response.body).to include("Old Reliable").and include("Amendment ready to send")
    end

    it "says so when nothing is in motion" do
      [ just_signed, out_for_signature, draft ].each(&:destroy!)
      get manage_contracts_path
      expect(response.body).to include("Nothing in motion")
      expect(response.body).not_to include("Old Reliable")
    end
  end

  describe "All Contracts" do
    let!(:later) { create(:contract, :active, organization: org, production: production, contractor_name: "Zed Venue", contract_start_date: 3.weeks.from_now) }
    let!(:sooner) { create(:contract, :active, organization: org, production: production, contractor_name: "Alpha Room", contract_start_date: 1.week.from_now) }
    let!(:undated_draft) { create(:contract, organization: org, production: production, contractor_name: "Maybe Later", contract_start_date: nil) }
    let!(:past) { create(:contract, :completed, organization: org, production: production, contractor_name: "Done And Dusted") }

    it "lists every current contract by upcoming date, drafts without a date last" do
      get all_manage_contracts_path
      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include("All Contracts")
      expect(body.index("Alpha Room")).to be < body.index("Zed Venue")
      expect(body.index("Zed Venue")).to be < body.index("Maybe Later")
      expect(body).not_to include("Done And Dusted")
    end

    it "sorts by name when asked" do
      get all_manage_contracts_path(sort: "name")
      body = response.body
      expect(body.index("Alpha Room")).to be < body.index("Maybe Later")
      expect(body.index("Maybe Later")).to be < body.index("Zed Venue")
    end
  end
end
