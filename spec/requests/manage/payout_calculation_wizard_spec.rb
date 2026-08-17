# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Payout calculation wizard", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, name: "Friday Cabaret") }

  # Wizard state rides in Rails.cache; the test env cache is a null store.
  let(:memory_cache) { ActiveSupport::Cache::MemoryStore.new }
  before { allow(Rails).to receive(:cache).and_return(memory_cache) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def start_wizard(**params)
    get manage_money_payout_calculation_wizard_start_path(**params)
    follow_redirect!
  end

  def name_it(name, description: "")
    post manage_money_payout_calculation_wizard_save_name_path, params: { name: name, description: description }
    expect(response).to redirect_to(manage_money_payout_calculation_wizard_approach_path)
  end

  def choose(approach)
    post manage_money_payout_calculation_wizard_save_approach_path, params: { approach: approach }
  end

  describe "the walk through each approach" do
    it "flat: name → approach → amounts → review → saved with a flat amount" do
      start_wizard
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("What should this calculation be called?")

      name_it("Fifty flat", description: "Everyone gets fifty")
      choose("flat")
      expect(response).to redirect_to(manage_money_payout_calculation_wizard_amounts_path)

      get manage_money_payout_calculation_wizard_amounts_path
      expect(response.body).to include('name="distribution[flat_amount]"')
      expect(response.body).to include("A flat amount each")

      post manage_money_payout_calculation_wizard_save_amounts_path, params: { distribution: { flat_amount: "60" } }
      # Flat pays no pool, so there is no "before" step.
      expect(response).to redirect_to(manage_money_payout_calculation_wizard_review_path)

      get manage_money_payout_calculation_wizard_review_path
      expect(response.body).to include("Fifty flat")
      expect(response.body).to include("flat per performer")
      expect(response.body).to include("$60.00 each")
      expect(response.body).not_to include("Before performers are paid</p>")

      expect {
        post manage_money_payout_calculation_wizard_save_path
      }.to change(PayoutScheme, :count).by(1)

      calc = PayoutScheme.order(:id).last
      expect(response).to redirect_to(manage_money_payout_calculation_path(calc))
      expect(calc.name).to eq("Fifty flat")
      expect(calc.description).to eq("Everyone gets fifty")
      expect(calc.rules["distribution"]).to eq({ "method" => "flat_fee", "flat_amount" => 60.0 })
      expect(calc.rules["allocation"]).to eq([])
      expect(calc.organization).to eq(org)
    end

    it "per act: a schedule of 75 then 50, then 40 for every act after" do
      start_wizard
      name_it("Act pay")
      choose("per_act")

      get manage_money_payout_calculation_wizard_amounts_path
      expect(response.body).to include('name="distribution[act_mode]"')
      expect(response.body).to include("1st act pays")
      expect(response.body).to include("2nd act pays")
      expect(response.body).to include("Add an act")
      expect(response.body).to include("Add a row")

      post manage_money_payout_calculation_wizard_save_amounts_path, params: {
        distribution: { act_mode: "schedule", act_rates: [ "75", "50" ], additional_act_rate: "40" }
      }
      expect(response).to redirect_to(manage_money_payout_calculation_wizard_review_path)

      # Back to the amounts step: the saved rows come back in order.
      get manage_money_payout_calculation_wizard_amounts_path
      expect(response.body).to include('name="distribution[act_rates][]" value="75.0"')
      expect(response.body).to include('name="distribution[act_rates][]" value="50.0"')
      expect(response.body).to include('name="distribution[additional_act_rate]" value="40.0"')

      get manage_money_payout_calculation_wizard_review_path
      expect(response.body).to include("1st act $75.00")
      expect(response.body).to include("2nd act $50.00")
      expect(response.body).to include("then $40.00 each")

      post manage_money_payout_calculation_wizard_save_path
      calc = PayoutScheme.order(:id).last
      expect(calc.rules["distribution"]).to eq({
        "method" => "per_act",
        "act_mode" => "schedule",
        "act_rates" => [ { "act" => 1, "amount" => 75.0 }, { "act" => 2, "amount" => 50.0 } ],
        "additional_act_rate" => 40.0
      })
    end

    it "per act: a table of tiers, blank rows dropped and sorted" do
      start_wizard
      name_it("Act table")
      choose("per_act")
      post manage_money_payout_calculation_wizard_save_amounts_path, params: {
        distribution: { act_mode: "tiers", tiers: { "0" => { acts: "2", amount: "50" }, "1" => { acts: "1", amount: "25" }, "2" => { acts: "", amount: "" } } }
      }

      # Back to the amounts step: the table comes back sorted, tiers mode picked.
      get manage_money_payout_calculation_wizard_amounts_path
      expect(response.body).to match(/value="tiers"\s+checked/)
      expect(response.body).to include('name="distribution[tiers][0][acts]" value="1"')
      expect(response.body).to include('name="distribution[tiers][1][acts]" value="2"')

      post manage_money_payout_calculation_wizard_save_path

      calc = PayoutScheme.order(:id).last
      expect(calc.rules["distribution"]).to eq({
        "method" => "per_act",
        "act_mode" => "tiers",
        "tiers" => [ { "acts" => 1, "amount" => 25.0 }, { "acts" => 2, "amount" => 50.0 } ]
      })
    end

    it "per ticket with a guaranteed minimum stores the guaranteed method" do
      start_wizard
      name_it("Door deal")
      choose("per_ticket")

      get manage_money_payout_calculation_wizard_amounts_path
      expect(response.body).to include('name="distribution[per_ticket_rate]"')
      expect(response.body).to include('name="distribution[guarantee_minimum]"')
      expect(response.body).to include('name="distribution[minimum]"')

      post manage_money_payout_calculation_wizard_save_amounts_path, params: {
        distribution: { per_ticket_rate: "2.5", guarantee_minimum: "1", minimum: "40" }
      }
      expect(response).to redirect_to(manage_money_payout_calculation_wizard_review_path)
      post manage_money_payout_calculation_wizard_save_path

      calc = PayoutScheme.order(:id).last
      expect(calc.rules["distribution"]).to eq({ "method" => "per_ticket_guaranteed", "per_ticket_rate" => 2.5, "minimum" => 40.0 })
    end

    it "per ticket without the minimum stores plain per_ticket" do
      start_wizard
      name_it("Door deal, no floor")
      choose("per_ticket")
      post manage_money_payout_calculation_wizard_save_amounts_path, params: { distribution: { per_ticket_rate: "3", minimum: "40" } }
      post manage_money_payout_calculation_wizard_save_path

      calc = PayoutScheme.order(:id).last
      expect(calc.rules["distribution"]).to eq({ "method" => "per_ticket", "per_ticket_rate" => 3.0 })
    end

    it "share by shares, with the house at 40%, expenses first and a producer's 5% cut" do
      producer = create(:person, name: "Pat Producer")
      org.people << producer

      start_wizard
      name_it("Door split")
      choose("share")

      get manage_money_payout_calculation_wizard_amounts_path
      expect(response.body).to include('name="distribution[split]"')
      expect(response.body).to include('name="distribution[default_shares]"')

      post manage_money_payout_calculation_wizard_save_amounts_path, params: { distribution: { split: "shares", default_shares: "1.5" } }
      # A pool approach has a "before performers are paid" step.
      expect(response).to redirect_to(manage_money_payout_calculation_wizard_before_path)

      get manage_money_payout_calculation_wizard_before_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="house_percentage"')
      expect(response.body).to include('name="expenses_first"')
      expect(response.body).to include("Pat Producer")
      expect(response.body).to include("performers share the other")

      post manage_money_payout_calculation_wizard_save_before_path, params: {
        house_percentage: "40", expenses_first: "1",
        individual_allocations: { "0" => { person_id: producer.id.to_s, percentage: "5", label: "Producer" }, "1" => { person_id: "", percentage: "10", label: "" } }
      }
      expect(response).to redirect_to(manage_money_payout_calculation_wizard_review_path)

      get manage_money_payout_calculation_wizard_review_path
      expect(response.body).to include("Expenses covered first")
      expect(response.body).to include("House keeps 40%")
      expect(response.body).to include("Producer gets 5%")
      expect(response.body).to include("Split by shares")

      post manage_money_payout_calculation_wizard_save_path
      calc = PayoutScheme.order(:id).last
      expect(calc.rules["distribution"]).to eq({ "method" => "shares", "default_shares" => 1.5 })
      expect(calc.rules["allocation"]).to eq([
        { "type" => "expenses_first" },
        { "type" => "percentage", "value" => 40.0, "label" => "House take" },
        { "type" => "percentage", "value" => 5.0, "person_id" => producer.id, "label" => "Producer" },
        { "type" => "remainder", "label" => "Performer pool" }
      ])
    end

    it "not paid skips amounts and before, and stores no_pay" do
      start_wizard
      name_it("Rehearsals")
      choose("not_paid")
      expect(response).to redirect_to(manage_money_payout_calculation_wizard_review_path)

      # Typing the skipped steps' URLs bounces on to review.
      get manage_money_payout_calculation_wizard_amounts_path
      expect(response).to redirect_to(manage_money_payout_calculation_wizard_review_path)
      get manage_money_payout_calculation_wizard_before_path
      expect(response).to redirect_to(manage_money_payout_calculation_wizard_review_path)

      get manage_money_payout_calculation_wizard_review_path
      expect(response.body).to include("Performers aren&#39;t paid")
      expect(response.body).not_to include("The amounts</p>")

      post manage_money_payout_calculation_wizard_save_path
      calc = PayoutScheme.order(:id).last
      expect(calc.rules["distribution"]).to eq({ "method" => "no_pay" })
      expect(calc.rules["allocation"]).to eq([])
    end
  end

  describe "the name step" do
    it "insists on a name" do
      start_wizard
      post manage_money_payout_calculation_wizard_save_name_path, params: { name: "   " }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Give the calculation a name")
    end
  end

  describe "defaults" do
    it "makes the calculation the chosen productions' default" do
      other = create(:production, organization: org, name: "Sunday Improv")

      start_wizard
      name_it("Fifty flat")
      choose("flat")
      post manage_money_payout_calculation_wizard_save_amounts_path, params: { distribution: { flat_amount: "50" } }

      get manage_money_payout_calculation_wizard_review_path
      expect(response.body).to include('name="default_production_ids[]"')
      expect(response.body).to include("Friday Cabaret")
      expect(response.body).to include("Sunday Improv")

      post manage_money_payout_calculation_wizard_save_path, params: { default_production_ids: [ production.id ] }

      calc = PayoutScheme.order(:id).last
      expect(PayoutScheme.current_default_for_production(production)).to eq(calc)
      expect(PayoutScheme.current_default_for_production(other)).to be_nil
    end

    it "start?production_id= for an act-based production defaults to per act and preselects it" do
      production.update!(casting_mode: "act_based")

      start_wizard(production_id: production.id)
      name_it("Act pay")

      get manage_money_payout_calculation_wizard_approach_path
      expect(response.body).to include("Recommended")
      # Per act is first and checked.
      body = response.body
      expect(body.index('value="per_act"')).to be < body.index('value="flat"')
      expect(body).to match(/value="per_act"\s+checked/)

      choose("per_act")
      post manage_money_payout_calculation_wizard_save_amounts_path, params: { distribution: { act_mode: "simple", per_act_rate: "30" } }

      get manage_money_payout_calculation_wizard_review_path
      expect(response.body).to match(/value="#{production.id}"\s+checked/)

      post manage_money_payout_calculation_wizard_save_path, params: { default_production_ids: [ production.id ] }
      calc = PayoutScheme.order(:id).last
      expect(calc.rules["distribution"]).to eq({ "method" => "per_act", "act_mode" => "simple", "per_act_rate" => 30.0 })
      expect(PayoutScheme.current_default_for_production(production)).to eq(calc)
    end

    it "honours return_to after saving" do
      start_wizard(return_to: "/manage/money/payouts")
      name_it("Fifty flat")
      choose("flat")
      post manage_money_payout_calculation_wizard_save_amounts_path, params: { distribution: { flat_amount: "50" } }
      post manage_money_payout_calculation_wizard_save_path

      expect(response).to redirect_to("/manage/money/payouts")
    end

    it "ignores a return_to that isn't ours" do
      start_wizard(return_to: "https://evil.example/phish")
      name_it("Fifty flat")
      choose("flat")
      post manage_money_payout_calculation_wizard_save_amounts_path, params: { distribution: { flat_amount: "50" } }
      post manage_money_payout_calculation_wizard_save_path

      calc = PayoutScheme.order(:id).last
      expect(response).to redirect_to(manage_money_payout_calculation_path(calc))
    end
  end

  describe "editing an existing calculation" do
    let!(:existing) do
      PayoutScheme.create!(
        organization: org, name: "House split", description: "The usual",
        rules: {
          "allocation" => [
            { "type" => "expenses_first" },
            { "type" => "percentage", "value" => 30.0, "label" => "House take" },
            { "type" => "remainder", "label" => "Performer pool" }
          ],
          "distribution" => { "method" => "equal" },
          "performer_overrides" => {}
        }
      )
    end

    it "start?id= seeds the wizard from the record and lands on review" do
      existing.make_production_scheme!(production)

      get manage_money_payout_calculation_wizard_start_path(id: existing.id)
      expect(response).to redirect_to(manage_money_payout_calculation_wizard_review_path)
      follow_redirect!

      expect(response.body).to include("Edit House split")
      expect(response.body).to include("The usual")
      expect(response.body).to include("A share of the night&#39;s money")
      expect(response.body).to include("House keeps 30%")
      expect(response.body).to include("Expenses covered first")
      expect(response.body).to match(/value="#{production.id}"\s+checked/)

      # The seeded state shows in the earlier steps too.
      get manage_money_payout_calculation_wizard_before_path
      expect(response.body).to include('name="house_percentage" value="30"')
      expect(response.body).to match(/name="expenses_first" value="1" checked/)
    end

    it "saves changes onto the same record" do
      get manage_money_payout_calculation_wizard_start_path(id: existing.id)
      post manage_money_payout_calculation_wizard_save_name_path, params: { name: "House split, revised" }
      post manage_money_payout_calculation_wizard_save_before_path, params: { house_percentage: "35", expenses_first: "0" }

      expect {
        post manage_money_payout_calculation_wizard_save_path, params: { default_production_ids: [ production.id ] }
      }.not_to change(PayoutScheme, :count)

      existing.reload
      expect(existing.name).to eq("House split, revised")
      expect(existing.rules["allocation"]).to eq([
        { "type" => "percentage", "value" => 35.0, "label" => "House take" },
        { "type" => "remainder", "label" => "Performer pool" }
      ])
      expect(PayoutScheme.current_default_for_production(production)).to eq(existing)
    end

    it "start?id=&duplicate=1 copies it into a new calculation" do
      get manage_money_payout_calculation_wizard_start_path(id: existing.id, duplicate: "1")
      expect(response).to redirect_to(manage_money_payout_calculation_wizard_name_path)
      follow_redirect!
      expect(response.body).to include("House split (copy)")

      post manage_money_payout_calculation_wizard_save_name_path, params: { name: "House split (copy)" }
      expect {
        post manage_money_payout_calculation_wizard_save_path
      }.to change(PayoutScheme, :count).by(1)
      expect(existing.reload.name).to eq("House split")
    end

    it "won't open a calculation from another organization" do
      other_org = create(:organization, :pro)
      foreign = PayoutScheme.create!(organization: other_org, name: "Not yours", rules: { "distribution" => { "method" => "equal" } })

      get manage_money_payout_calculation_wizard_start_path(id: foreign.id)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "cancel" do
    it "clears the wizard and goes back to the calculations list" do
      start_wizard
      name_it("Half done")

      delete manage_money_payout_calculation_wizard_cancel_path
      expect(response).to redirect_to(manage_money_payout_calculations_path)

      get manage_money_payout_calculation_wizard_name_path
      expect(response.body).not_to include("Half done")
    end
  end

  describe "on the free plan" do
    before { org.update!(comped_indefinitely: false, subscription_status: nil) }

    it "is paywalled" do
      get manage_money_payout_calculation_wizard_start_path

      expect(response).to have_http_status(:payment_required)
      expect(response.body).to include("Money &amp; Payments")
      expect(response.body).to include("Choose annual")
    end
  end
end
