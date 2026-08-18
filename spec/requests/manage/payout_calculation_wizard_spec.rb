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

  def choose(approach)
    post manage_money_payout_calculation_wizard_save_approach_path, params: { approach: approach }
  end

  def pick_who(*production_ids, starting: "now", starting_on: nil)
    post manage_money_payout_calculation_wizard_save_who_path,
         params: { default_production_ids: production_ids, starting: starting, starting_on: starting_on }
    expect(response).to redirect_to(manage_money_payout_calculation_wizard_review_path)
  end

  def save_it(name:, description: "")
    post manage_money_payout_calculation_wizard_save_path, params: { name: name, description: description }
  end

  describe "the walk through each approach" do
    it "flat: approach → amounts → who → review → saved with a flat amount and the name from review" do
      start_wizard
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("How are performers paid?")
      # Not paid is no longer an approach — a show nobody pays has no calculation.
      expect(response.body).not_to include('value="not_paid"')

      choose("flat")
      expect(response).to redirect_to(manage_money_payout_calculation_wizard_amounts_path)

      get manage_money_payout_calculation_wizard_amounts_path
      expect(response.body).to include('name="distribution[flat_amount]"')
      expect(response.body).to include("A flat amount each")

      post manage_money_payout_calculation_wizard_save_amounts_path, params: { distribution: { flat_amount: "60" } }
      # Flat pays no pool, so there is no "before" step; straight on to who uses it.
      expect(response).to redirect_to(manage_money_payout_calculation_wizard_who_path)

      get manage_money_payout_calculation_wizard_who_path
      expect(response.body).to include("Which productions should use this calculation?")
      expect(response.body).to include("Friday Cabaret")
      expect(response.body).to include("None yet")
      pick_who

      get manage_money_payout_calculation_wizard_review_path
      expect(response.body).to include("flat per performer")
      expect(response.body).to include("$60.00 each")
      expect(response.body).not_to include("Before performers are paid</p>")
      # The name field, prefilled with a suggestion read off the calculation.
      expect(response.body).to include('name="name"')
      expect(response.body).to include('value="$60 flat per performer"')
      expect(response.body).to include('name="description"')

      expect {
        save_it(name: "Sixty flat", description: "Everyone gets sixty")
      }.to change(PayoutScheme, :count).by(1)

      calc = PayoutScheme.order(:id).last
      expect(response).to redirect_to(manage_money_payout_calculation_path(calc))
      expect(calc.name).to eq("Sixty flat")
      expect(calc.description).to eq("Everyone gets sixty")
      expect(calc.rules["distribution"]).to eq({ "method" => "flat_fee", "flat_amount" => 60.0 })
      expect(calc.rules["allocation"]).to eq([])
      expect(calc.organization).to eq(org)
    end

    it "per act: the same rate for every act is the starter" do
      start_wizard
      choose("per_act")

      get manage_money_payout_calculation_wizard_amounts_path
      expect(response.body).to include('name="distribution[act_mode]"')
      expect(response.body).to match(/value="simple"\s+checked/)
      expect(response.body).to include('name="distribution[per_act_rate]" value="25"')
      expect(response.body).to include("A table by how many acts they do")
      expect(response.body).to include("Each act beyond that")
      # The positional schedule is gone from the wizard.
      expect(response.body).not_to include('value="schedule"')
      expect(response.body).not_to include("distribution[act_rates]")

      post manage_money_payout_calculation_wizard_save_amounts_path, params: { distribution: { act_mode: "simple", per_act_rate: "30" } }
      pick_who
      get manage_money_payout_calculation_wizard_review_path
      expect(response.body).to include('value="$30 per act"')

      save_it(name: "$30 per act")
      calc = PayoutScheme.order(:id).last
      expect(calc.rules["distribution"]).to eq({ "method" => "per_act", "act_mode" => "simple", "per_act_rate" => 30.0 })
    end

    it "per act: a table of tiers with a rate for every act beyond it, blank rows dropped and sorted" do
      start_wizard
      choose("per_act")
      post manage_money_payout_calculation_wizard_save_amounts_path, params: {
        distribution: {
          act_mode: "tiers",
          tiers: { "0" => { acts: "2", amount: "125" }, "1" => { acts: "1", amount: "75" }, "2" => { acts: "", amount: "" } },
          additional_act_rate: "50"
        }
      }
      expect(response).to redirect_to(manage_money_payout_calculation_wizard_who_path)

      # Back to the amounts step: the table comes back sorted, tiers mode picked, the beyond rate kept.
      get manage_money_payout_calculation_wizard_amounts_path
      expect(response.body).to match(/value="tiers"\s+checked/)
      expect(response.body).to include('name="distribution[tiers][0][acts]" value="1"')
      expect(response.body).to include('name="distribution[tiers][0][amount]" value="75"')
      expect(response.body).to include('name="distribution[tiers][1][acts]" value="2"')
      expect(response.body).to include('name="distribution[tiers][1][amount]" value="125"')
      expect(response.body).to include('name="distribution[additional_act_rate]" value="50"')

      pick_who
      get manage_money_payout_calculation_wizard_review_path
      expect(response.body).to include("1 act $75.00, 2 acts $125.00, then $50.00 per act")
      expect(response.body).to include('value="1 act $75, 2 acts $125, then $50 each"')

      save_it(name: "Act table")
      calc = PayoutScheme.order(:id).last
      expect(calc.rules["distribution"]).to eq({
        "method" => "per_act",
        "act_mode" => "tiers",
        "tiers" => [ { "acts" => 1, "amount" => 75.0 }, { "acts" => 2, "amount" => 125.0 } ],
        "additional_act_rate" => 50.0
      })
      expect(PayoutScheme.act_amount(calc.distribution_config, 4)).to eq(225.0)
    end

    it "per act: show roles priced by name, prefilled from the organization's show roles, with the stacking kept" do
      act_production = create(:production, organization: org, casting_mode: "act_based", name: "Burlesque")
      create(:role, production: act_production, name: "MC", standing: true, position: 0)
      create(:role, production: act_production, name: "Stage Kitten", standing: true, quantity: 2, position: 1)
      create(:role, production: act_production, name: "Magic", position: 2)
      # Another org's show roles never leak in
      create(:role, production: create(:production, casting_mode: "act_based"), name: "Host", standing: true)

      start_wizard
      choose("per_act")
      get manage_money_payout_calculation_wizard_amounts_path
      expect(response.body).to include("Show roles")
      expect(response.body).to include('name="distribution[role_amounts][0][name]" value="MC"')
      expect(response.body).to include('name="distribution[role_amounts][1][name]" value="Stage Kitten"')
      expect(response.body).not_to include('value="Host"')
      expect(response.body).not_to include('value="Magic"')
      expect(response.body).to match(/name="distribution\[role_stacking\]" value="both" checked/)

      post manage_money_payout_calculation_wizard_save_amounts_path, params: {
        distribution: {
          act_mode: "tiers",
          tiers: { "0" => { acts: "1", amount: "75" }, "1" => { acts: "2", amount: "125" } },
          role_amounts: { "0" => { name: "MC", amount: "100" }, "1" => { name: "Stage Kitten", amount: "35" }, "2" => { name: "Usher", amount: "" } },
          role_stacking: "higher"
        }
      }
      expect(response).to redirect_to(manage_money_payout_calculation_wizard_who_path)

      get manage_money_payout_calculation_wizard_amounts_path
      expect(response.body).to include('name="distribution[role_amounts][0][name]" value="MC"')
      expect(response.body).to include('name="distribution[role_amounts][0][amount]" value="100"')
      expect(response.body).to include('name="distribution[role_amounts][1][amount]" value="35"')
      expect(response.body).not_to include('value="Usher"')
      expect(response.body).to match(/name="distribution\[role_stacking\]" value="higher" checked/)

      pick_who(act_production.id)
      get manage_money_payout_calculation_wizard_review_path
      expect(response.body).to include("MC $100.00, Stage Kitten $35.00 — or act pay, whichever is higher")

      save_it(name: "Burlesque pay")
      calc = PayoutScheme.order(:id).last
      expect(calc.rules["distribution"]).to eq({
        "method" => "per_act",
        "act_mode" => "tiers",
        "tiers" => [ { "acts" => 1, "amount" => 75.0 }, { "acts" => 2, "amount" => 125.0 } ],
        "role_amounts" => [ { "name" => "MC", "amount" => 100.0 }, { "name" => "Stage Kitten", "amount" => 35.0 } ],
        "role_stacking" => "higher"
      })
      expect(calc.rules_summary).to include("Show roles: MC $100.00, Stage Kitten $35.00 — or act pay, whichever is higher")

      # Editing brings the priced rows back rather than the suggestions
      start_wizard(id: calc.id)
      get manage_money_payout_calculation_wizard_amounts_path
      expect(response.body).to include('name="distribution[role_amounts][0][amount]" value="100"')
    end

    it "per act: a table without a beyond rate stores no beyond rate" do
      start_wizard
      choose("per_act")
      post manage_money_payout_calculation_wizard_save_amounts_path, params: {
        distribution: { act_mode: "tiers", tiers: { "0" => { acts: "1", amount: "25" }, "1" => { acts: "2", amount: "50" } }, additional_act_rate: "" }
      }
      pick_who
      get manage_money_payout_calculation_wizard_review_path
      expect(response.body).to include("1 act $25.00, 2+ acts $50.00")

      save_it(name: "Capped table")
      calc = PayoutScheme.order(:id).last
      expect(calc.rules["distribution"]).to eq({
        "method" => "per_act", "act_mode" => "tiers",
        "tiers" => [ { "acts" => 1, "amount" => 25.0 }, { "acts" => 2, "amount" => 50.0 } ]
      })
    end

    it "per ticket with a guaranteed minimum stores the guaranteed method" do
      start_wizard
      choose("per_ticket")

      get manage_money_payout_calculation_wizard_amounts_path
      expect(response.body).to include('name="distribution[per_ticket_rate]"')
      expect(response.body).to include('name="distribution[guarantee_minimum]"')
      expect(response.body).to include('name="distribution[minimum]"')

      post manage_money_payout_calculation_wizard_save_amounts_path, params: {
        distribution: { per_ticket_rate: "2.5", guarantee_minimum: "1", minimum: "40" }
      }
      expect(response).to redirect_to(manage_money_payout_calculation_wizard_who_path)
      pick_who
      get manage_money_payout_calculation_wizard_review_path
      expect(response.body).to include('value="$2.50/ticket, min $40"')

      save_it(name: "Door deal")
      calc = PayoutScheme.order(:id).last
      expect(calc.rules["distribution"]).to eq({ "method" => "per_ticket_guaranteed", "per_ticket_rate" => 2.5, "minimum" => 40.0 })
    end

    it "per ticket without the minimum stores plain per_ticket" do
      start_wizard
      choose("per_ticket")
      post manage_money_payout_calculation_wizard_save_amounts_path, params: { distribution: { per_ticket_rate: "3", minimum: "40" } }
      pick_who
      save_it(name: "Door deal, no floor")

      calc = PayoutScheme.order(:id).last
      expect(calc.rules["distribution"]).to eq({ "method" => "per_ticket", "per_ticket_rate" => 3.0 })
    end

    it "share by shares, with the house at 40%, expenses first and a producer's 5% cut" do
      producer = create(:person, name: "Pat Producer")
      org.people << producer

      start_wizard
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
      expect(response).to redirect_to(manage_money_payout_calculation_wizard_who_path)
      pick_who

      get manage_money_payout_calculation_wizard_review_path
      expect(response.body).to include("Expenses covered first")
      expect(response.body).to include("House keeps 40%")
      expect(response.body).to include("Producer gets 5%")
      expect(response.body).to include("Split by shares")
      expect(response.body).to include('value="Split by shares"')

      save_it(name: "Door split")
      calc = PayoutScheme.order(:id).last
      expect(calc.rules["distribution"]).to eq({ "method" => "shares", "default_shares" => 1.5 })
      expect(calc.rules["allocation"]).to eq([
        { "type" => "expenses_first" },
        { "type" => "percentage", "value" => 40.0, "label" => "House take" },
        { "type" => "percentage", "value" => 5.0, "person_id" => producer.id, "label" => "Producer" },
        { "type" => "remainder", "label" => "Performer pool" }
      ])
    end

    it "an even split with a house cut suggests its name from the cut" do
      start_wizard
      choose("share")
      post manage_money_payout_calculation_wizard_save_amounts_path, params: { distribution: { split: "equal" } }
      post manage_money_payout_calculation_wizard_save_before_path, params: { house_percentage: "40" }
      pick_who

      get manage_money_payout_calculation_wizard_review_path
      expect(response.body).to include('value="Even split after 40% house"')
    end

    it "an unknown approach falls back to the starter rather than not paid" do
      start_wizard
      choose("not_paid")
      expect(response).to redirect_to(manage_money_payout_calculation_wizard_amounts_path)

      get manage_money_payout_calculation_wizard_amounts_path
      expect(response.body).to include('name="distribution[flat_amount]"')
    end
  end

  describe "the name on the review step" do
    before do
      start_wizard
      choose("flat")
      post manage_money_payout_calculation_wizard_save_amounts_path, params: { distribution: { flat_amount: "50" } }
      pick_who
    end

    it "insists on a name" do
      save_it(name: "   ")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Give the calculation a name")
      expect(PayoutScheme.count).to eq(0)
    end

    it "keeps the name typed when the record itself is invalid" do
      PayoutScheme.create!(organization: org, name: "Taken", rules: { "distribution" => { "method" => "equal" } })

      save_it(name: "Taken")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Name has already been taken")
      expect(response.body).to include('value="Taken"')
    end
  end

  describe "who uses it" do
    let!(:other) { create(:production, organization: org, name: "Sunday Improv") }

    def flat_through_amounts
      start_wizard
      choose("flat")
      post manage_money_payout_calculation_wizard_save_amounts_path, params: { distribution: { flat_amount: "50" } }
    end

    it "makes the calculation the chosen productions' default, starting now" do
      flat_through_amounts

      get manage_money_payout_calculation_wizard_who_path
      expect(response.body).to include('name="default_production_ids[]"')
      expect(response.body).to include("Friday Cabaret")
      expect(response.body).to include("Sunday Improv")
      expect(response.body).to include('name="starting" value="now"')
      expect(response.body).to include('name="starting_on"')

      pick_who(production.id)
      get manage_money_payout_calculation_wizard_review_path
      expect(response.body).to include("Who uses it")
      expect(response.body).to include("Friday Cabaret")
      expect(response.body).to include("starting now")
      expect(response.body).not_to include("Sunday Improv")

      save_it(name: "Fifty flat")

      calc = PayoutScheme.order(:id).last
      expect(PayoutScheme.current_default_for_production(production)).to eq(calc)
      expect(PayoutScheme.current_default_for_production(other)).to be_nil
    end

    it "shows what a production uses today, and that checking it will switch" do
      current = PayoutScheme.create!(organization: org, name: "House split", rules: { "distribution" => { "method" => "equal" } })
      current.make_production_scheme!(production)

      flat_through_amounts
      get manage_money_payout_calculation_wizard_who_path

      expect(response.body).to include("Currently uses")
      expect(response.body).to include("House split")
      expect(response.body).to include("Will switch from House split to this calculation")
      # Sunday Improv has nothing yet.
      expect(response.body).to include("None yet")
    end

    it "can start on a date, leaving earlier shows on what they use today" do
      old = PayoutScheme.create!(organization: org, name: "House split", rules: { "distribution" => { "method" => "equal" } })
      old.make_production_scheme!(production)
      soon = create(:show, production: production, date_and_time: 1.week.from_now)
      later = create(:show, production: production, date_and_time: 5.weeks.from_now)
      switch = 3.weeks.from_now.to_date

      flat_through_amounts
      pick_who(production.id, starting: "date", starting_on: switch.iso8601)

      get manage_money_payout_calculation_wizard_review_path
      expect(response.body).to include("starting #{I18n.l(switch, format: :long)}")

      save_it(name: "Fifty flat")
      calc = PayoutScheme.order(:id).last
      expect(PayoutScheme.default_for_show(soon)).to eq(old)
      expect(PayoutScheme.default_for_show(later)).to eq(calc)
    end

    it "start?production_id= for an act-based production defaults to per act and preselects it" do
      production.update!(casting_mode: "act_based")

      start_wizard(production_id: production.id)
      expect(response.body).to include("Recommended")
      # Per act is first and checked.
      body = response.body
      expect(body.index('value="per_act"')).to be < body.index('value="flat"')
      expect(body).to match(/value="per_act"\s+checked/)

      choose("per_act")
      post manage_money_payout_calculation_wizard_save_amounts_path, params: { distribution: { act_mode: "simple", per_act_rate: "30" } }

      get manage_money_payout_calculation_wizard_who_path
      expect(response.body).to match(/value="#{production.id}"\s+checked/)

      pick_who(production.id)
      save_it(name: "Act pay")
      calc = PayoutScheme.order(:id).last
      expect(calc.rules["distribution"]).to eq({ "method" => "per_act", "act_mode" => "simple", "per_act_rate" => 30.0 })
      expect(PayoutScheme.current_default_for_production(production)).to eq(calc)
    end

    it "honours return_to after saving" do
      start_wizard(return_to: "/manage/money/payouts")
      choose("flat")
      post manage_money_payout_calculation_wizard_save_amounts_path, params: { distribution: { flat_amount: "50" } }
      pick_who
      save_it(name: "Fifty flat")

      expect(response).to redirect_to("/manage/money/payouts")
    end

    it "ignores a return_to that isn't ours" do
      start_wizard(return_to: "https://evil.example/phish")
      choose("flat")
      post manage_money_payout_calculation_wizard_save_amounts_path, params: { distribution: { flat_amount: "50" } }
      pick_who
      save_it(name: "Fifty flat")

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

    it "start?id= seeds the wizard from the record and walks it from the first step, prefilled" do
      existing.make_production_scheme!(production)

      get manage_money_payout_calculation_wizard_start_path(id: existing.id)
      expect(response).to redirect_to(manage_money_payout_calculation_wizard_approach_path)
      follow_redirect!
      expect(response.body).to include("Edit House split")
      expect(response.body).to match(/value="share"\s+checked/)

      get manage_money_payout_calculation_wizard_review_path
      expect(response.body).to include("Edit House split")
      expect(response.body).to include('value="House split"')
      expect(response.body).to include("The usual")
      expect(response.body).to include("A share of the night&#39;s money")
      expect(response.body).to include("House keeps 30%")
      expect(response.body).to include("Expenses covered first")
      expect(response.body).to include("Friday Cabaret")

      # The seeded state shows in the earlier steps too.
      get manage_money_payout_calculation_wizard_before_path
      expect(response.body).to include('name="house_percentage" value="30"')
      expect(response.body).to match(/name="expenses_first" value="1" checked/)

      # And the production it already serves is checked, with no switch note.
      get manage_money_payout_calculation_wizard_who_path
      expect(response.body).to match(/value="#{production.id}"\s+checked/)
      expect(response.body).to include("Currently uses")
      expect(response.body).not_to include("Will switch from")
    end

    it "saves changes onto the same record" do
      get manage_money_payout_calculation_wizard_start_path(id: existing.id)
      post manage_money_payout_calculation_wizard_save_before_path, params: { house_percentage: "35", expenses_first: "0" }
      pick_who(production.id)

      expect {
        save_it(name: "House split, revised")
      }.not_to change(PayoutScheme, :count)

      existing.reload
      expect(existing.name).to eq("House split, revised")
      expect(existing.rules["allocation"]).to eq([
        { "type" => "percentage", "value" => 35.0, "label" => "House take" },
        { "type" => "remainder", "label" => "Performer pool" }
      ])
      expect(PayoutScheme.current_default_for_production(production)).to eq(existing)
    end

    it "keeps an older calculation's per-person exceptions across an edit" do
      existing.update!(rules: existing.rules.merge("performer_overrides" => { "Person_7" => { "flat_amount" => 100.0 } }))

      get manage_money_payout_calculation_wizard_start_path(id: existing.id)
      save_it(name: "House split, revised")

      expect(existing.reload.rules["performer_overrides"]).to eq("Person_7" => { "flat_amount" => 100.0 })
    end

    it "unchecking a production on edit leaves it with no calculation" do
      other = create(:production, organization: org, name: "Sunday Sketch")
      existing.make_production_scheme!(production)
      existing.make_production_scheme!(other)

      get manage_money_payout_calculation_wizard_start_path(id: existing.id)
      pick_who(other.id)
      save_it(name: existing.name)

      expect(PayoutScheme.current_default_for_production(other)).to eq(existing)
      expect(PayoutScheme.current_default_for_production(production)).to be_nil
    end

    it "unchecking a production on edit takes only this calculation's rows, leaving another's history in place" do
      other_calc = PayoutScheme.create!(organization: org, name: "Old flat", rules: { "distribution" => { "method" => "flat_fee", "flat_amount" => 40 } })
      create(:show, production: production, date_and_time: 3.weeks.ago)
      other_calc.make_production_scheme!(production) # reaches back three weeks
      existing.make_production_scheme!(production)   # from today

      get manage_money_payout_calculation_wizard_start_path(id: existing.id)
      pick_who
      save_it(name: existing.name)

      expect(PayoutSchemeDefault.for_production(production).map(&:payout_scheme)).to eq([ other_calc ])
      expect(PayoutScheme.current_default_for_production(production)).to eq(other_calc)
    end

    it "a rename that never opens the who step leaves the productions' history and scheduled switches alone" do
      other_calc = PayoutScheme.create!(organization: org, name: "Old flat", rules: { "distribution" => { "method" => "flat_fee", "flat_amount" => 40 } })
      later_calc = PayoutScheme.create!(organization: org, name: "Next year", rules: { "distribution" => { "method" => "flat_fee", "flat_amount" => 60 } })
      create(:show, production: production, date_and_time: 3.weeks.ago)
      other_calc.make_production_scheme!(production)                                   # history, three weeks back
      existing.make_production_scheme!(production)                                     # today
      later_calc.make_production_scheme!(production, starting_on: 6.weeks.from_now.to_date) # scheduled switch
      before = PayoutSchemeDefault.for_production(production).order(:effective_from).map { |r| [ r.payout_scheme_id, r.effective_from ] }

      get manage_money_payout_calculation_wizard_start_path(id: existing.id)
      save_it(name: "House split (renamed)")

      expect(existing.reload.name).to eq("House split (renamed)")
      after = PayoutSchemeDefault.for_production(production).order(:effective_from).map { |r| [ r.payout_scheme_id, r.effective_from ] }
      expect(after).to eq(before)
      expect(after.size).to eq(3)
    end

    it "re-saving with the who step visited doesn't rewrite a production that already used it" do
      later_calc = PayoutScheme.create!(organization: org, name: "Next year", rules: { "distribution" => { "method" => "flat_fee", "flat_amount" => 60 } })
      create(:show, production: production, date_and_time: 3.weeks.ago)
      existing.make_production_scheme!(production)                                     # reaches back three weeks
      later_calc.make_production_scheme!(production, starting_on: 6.weeks.from_now.to_date) # scheduled switch
      before = PayoutSchemeDefault.for_production(production).order(:effective_from).map { |r| [ r.payout_scheme_id, r.effective_from ] }

      get manage_money_payout_calculation_wizard_start_path(id: existing.id)
      pick_who(production.id)
      save_it(name: existing.name)

      after = PayoutSchemeDefault.for_production(production).order(:effective_from).map { |r| [ r.payout_scheme_id, r.effective_from ] }
      expect(after).to eq(before)
    end

    it "start?id=&duplicate=1 copies it into a new calculation" do
      get manage_money_payout_calculation_wizard_start_path(id: existing.id, duplicate: "1")
      expect(response).to redirect_to(manage_money_payout_calculation_wizard_approach_path)

      pick_who
      get manage_money_payout_calculation_wizard_review_path
      expect(response.body).to include('value="House split (copy)"')

      expect {
        save_it(name: "House split (copy)")
      }.to change(PayoutScheme, :count).by(1)
      expect(existing.reload.name).to eq("House split")
    end

    it "opens a legacy not-paid calculation as a flat $0" do
      legacy = PayoutScheme.create!(organization: org, name: "Rehearsals", rules: { "allocation" => [], "distribution" => { "method" => "no_pay" } })

      get manage_money_payout_calculation_wizard_start_path(id: legacy.id)
      get manage_money_payout_calculation_wizard_amounts_path

      expect(response.body).to include('name="distribution[flat_amount]" value="0"')
      expect(response.body).to include("was set up as \"not paid\"")
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
      choose("per_ticket")

      delete manage_money_payout_calculation_wizard_cancel_path
      expect(response).to redirect_to(manage_money_payout_calculations_path)

      get manage_money_payout_calculation_wizard_approach_path
      expect(response.body).to match(/value="flat"\s+checked/)
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
