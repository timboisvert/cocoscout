# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::PayoutSchemes", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  describe "act-based schemes" do
    it "offers Per Act as a way to pay performers" do
      get manage_new_money_payout_scheme_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Per Act")
      expect(response.body).to include('value="per_act"')
    end

    it "offers a Per Act preset" do
      get manage_presets_money_payout_schemes_path

      expect(response.body).to include("Per Act")
      expect(response.body).to include("2nd act")
    end

    it "saves a table of act counts, sorted and without blank rows" do
      post manage_money_payout_schemes_path, params: {
        payout_scheme: { name: "House Act Pay" },
        rules: {
          distribution: {
            method: "per_act",
            act_mode: "tiers",
            tiers: {
              "0" => { acts: "2", amount: "50" },
              "1" => { acts: "1", amount: "25" },
              "2" => { acts: "", amount: "" }
            }
          }
        }
      }

      scheme = PayoutScheme.find_by(name: "House Act Pay")
      expect(scheme.distribution_config["method"]).to eq("per_act")
      expect(scheme.distribution_config["tiers"]).to eq([
        { "acts" => 1, "amount" => 25.0 },
        { "acts" => 2, "amount" => 50.0 }
      ])
    end

    it "saves a rate for each act, numbered by position" do
      post manage_money_payout_schemes_path, params: {
        payout_scheme: { name: "Descending Act Pay" },
        rules: {
          distribution: {
            method: "per_act",
            act_mode: "schedule",
            act_rates: [ "75", "50" ],
            additional_act_rate: "25"
          }
        }
      }

      scheme = PayoutScheme.find_by(name: "Descending Act Pay")
      expect(scheme.distribution_config["act_mode"]).to eq("schedule")
      expect(scheme.distribution_config["act_rates"]).to eq([
        { "act" => 1, "amount" => 75.0 },
        { "act" => 2, "amount" => 50.0 }
      ])
      expect(scheme.distribution_config["additional_act_rate"]).to eq(25.0)
      expect(PayoutScheme.act_amount(scheme.distribution_config, 2)).to eq(125.0)
    end

    it "leaves the additional rate unset when it's left blank" do
      post manage_money_payout_schemes_path, params: {
        payout_scheme: { name: "Two Acts Only" },
        rules: {
          distribution: {
            method: "per_act", act_mode: "schedule", act_rates: [ "75", "50" ], additional_act_rate: ""
          }
        }
      }

      scheme = PayoutScheme.find_by(name: "Two Acts Only")
      expect(scheme.distribution_config["additional_act_rate"]).to be_nil
      expect(PayoutScheme.act_amount(scheme.distribution_config, 4)).to eq(125.0)
      expect(scheme.act_rules_description).to eq("1st act $75.00, 2nd act $50.00")
    end

    it "saves a flat rate per act" do
      post manage_money_payout_schemes_path, params: {
        payout_scheme: { name: "Twenty A Set" },
        rules: { distribution: { method: "per_act", act_mode: "simple", per_act_rate: "20" } }
      }

      scheme = PayoutScheme.find_by(name: "Twenty A Set")
      expect(scheme.distribution_config["act_mode"]).to eq("simple")
      expect(scheme.distribution_config["per_act_rate"]).to eq(20.0)
      expect(PayoutScheme.act_amount(scheme.distribution_config, 3)).to eq(60.0)
    end

    it "saves a per-person act rate exception" do
      person = create(:person)

      post manage_money_payout_schemes_path, params: {
        payout_scheme: { name: "Act Pay With Exception" },
        rules: {
          distribution: { method: "per_act", act_mode: "simple", per_act_rate: "20" },
          performer_overrides: { person.id.to_s => { person_id: person.id.to_s, per_act_rate: "35" } }
        }
      }

      scheme = PayoutScheme.find_by(name: "Act Pay With Exception")
      expect(scheme.performer_overrides[person.id.to_s]).to eq("per_act_rate" => 35.0)
    end

    it "spells out the act rules on the scheme page" do
      scheme = PayoutScheme.create!(
        organization: org,
        name: "Act Pay",
        rules: {
          "distribution" => {
            "method" => "per_act",
            "act_mode" => "tiers",
            "tiers" => [ { "acts" => 1, "amount" => 25.0 }, { "acts" => 2, "amount" => 50.0 } ]
          }
        }
      )

      get manage_money_payout_scheme_path(scheme)

      expect(response.body).to include("1 act $25.00, 2+ acts $50.00")
    end

    it "offers all three ways of working out act pay" do
      get manage_new_money_payout_scheme_path

      expect(response.body).to include('value="simple"')
      expect(response.body).to include('value="schedule"')
      expect(response.body).to include('value="tiers"')
      expect(response.body).to include("A different rate for each act")
    end

    it "renders the edit form for an existing act scheme" do
      scheme = PayoutScheme.create!(
        organization: org,
        name: "Act Pay",
        rules: {
          "distribution" => {
            "method" => "per_act",
            "act_mode" => "tiers",
            "tiers" => [ { "acts" => 1, "amount" => 25.0 } ]
          }
        }
      )

      get manage_edit_money_payout_scheme_path(scheme)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("rules[distribution][tiers][0][acts]")
    end
  end

  describe "starting from an act-based production" do
    let!(:act_production) { create(:production, organization: org, name: "Cabaret Night", casting_mode: "act_based") }
    let(:other_org_production) { create(:production, casting_mode: "act_based") }

    it "lights up the Per Act preset and pins it to the production" do
      get manage_presets_money_payout_schemes_path(preset: "per_act", production_id: act_production.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Recommended")
      expect(response.body).to include("Cabaret Night")
      expect(response.body).to include(%(name="production_id" id="production_id" value="#{act_production.id}"))
      # The recommended preset comes first
      expect(response.body.index('data-preset="per_act"')).to be < response.body.index('data-preset="no_pay"')
    end

    it "makes the preset scheme the production's default on create" do
      post manage_create_from_preset_money_payout_schemes_path, params: { preset_key: "per_act", production_id: act_production.id }

      scheme = PayoutScheme.find_by(name: "Per Act")
      expect(scheme).to be_present
      expect(response).to redirect_to(manage_edit_money_payout_scheme_path(scheme))
      expect(PayoutScheme.current_default_for_production(act_production)).to eq(scheme)
    end

    it "starts a custom scheme from per-act pay for that production" do
      get manage_new_money_payout_scheme_path(production_id: act_production.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(value="per_act" checked))
      expect(response.body).to include("This scheme will become the default for")
      expect(response.body).to include("Cabaret Night")
    end

    it "does not bias a role-based production toward per-act pay" do
      get manage_new_money_payout_scheme_path(production_id: production.id)

      expect(response.body).not_to include(%(value="per_act" checked))
      expect(response.body).not_to include("This scheme will become the default for")
    end

    it "ignores a production from another organization" do
      get manage_new_money_payout_scheme_path(production_id: other_org_production.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("This scheme will become the default for")

      post manage_create_from_preset_money_payout_schemes_path, params: { preset_key: "per_act", production_id: other_org_production.id }
      expect(PayoutScheme.current_default_for_production(other_org_production)).to be_nil
    end

    it "sets the default when a custom scheme is created from that production" do
      post manage_money_payout_schemes_path, params: {
        production_id: act_production.id,
        payout_scheme: { name: "House Act Pay" },
        rules: { distribution: { method: "per_act", act_mode: "simple", per_act_rate: "30" } }
      }

      scheme = PayoutScheme.find_by(name: "House Act Pay")
      expect(scheme).to be_present
      expect(PayoutScheme.current_default_for_production(act_production)).to eq(scheme)
    end
  end

  describe "PayoutScheme.act_amount" do
    let(:tiered) do
      { "act_mode" => "tiers", "tiers" => [ { "acts" => 1, "amount" => 25.0 }, { "acts" => 2, "amount" => 50.0 } ] }
    end

    it "pays nothing for no acts" do
      expect(PayoutScheme.act_amount(tiered, 0)).to eq(0.0)
    end

    it "pays the tier the count reaches" do
      expect(PayoutScheme.act_amount(tiered, 1)).to eq(25.0)
      expect(PayoutScheme.act_amount(tiered, 2)).to eq(50.0)
    end

    it "pays the top tier above the table" do
      expect(PayoutScheme.act_amount(tiered, 9)).to eq(50.0)
    end

    it "pays nothing below the first tier" do
      sparse = { "act_mode" => "tiers", "tiers" => [ { "acts" => 3, "amount" => 100.0 } ] }
      expect(PayoutScheme.act_amount(sparse, 2)).to eq(0.0)
    end

    context "with a rate for each act" do
      let(:schedule) do
        {
          "act_mode" => "schedule",
          "act_rates" => [ { "act" => 1, "amount" => 75.0 }, { "act" => 2, "amount" => 50.0 } ],
          "additional_act_rate" => 25.0
        }
      end

      it "adds the acts up rather than picking one amount" do
        expect(PayoutScheme.act_amount(schedule, 1)).to eq(75.0)
        expect(PayoutScheme.act_amount(schedule, 2)).to eq(125.0)
        expect(PayoutScheme.act_amount(schedule, 3)).to eq(150.0)
      end

      it "pays nothing for no acts" do
        expect(PayoutScheme.act_amount(schedule, 0)).to eq(0.0)
      end

      it "numbers a bare list of amounts by position" do
        bare = { "act_mode" => "schedule", "act_rates" => [ 75.0, 50.0 ] }
        expect(PayoutScheme.act_amount(bare, 2)).to eq(125.0)
      end
    end
  end

  describe "setting a scheme as a production default from the schemes page" do
    let!(:flat_scheme) do
      PayoutScheme.create!(organization: org, name: "Flat Fifty",
                           rules: { "distribution" => { "method" => "flat_fee", "flat_amount" => 50.0 } })
    end
    let!(:act_scheme) do
      PayoutScheme.create!(organization: org, name: "Act Pay",
                           rules: { "distribution" => { "method" => "per_act", "act_mode" => "simple", "per_act_rate" => 25.0 } })
    end

    it "restamps payouts nobody has calculated yet, and leaves calculated ones alone" do
      show = create(:show, production: production, date_and_time: 2.days.ago)
      pending = ShowPayout.create!(show: show, payout_scheme: flat_scheme)
      calculated = ShowPayout.create!(show: create(:show, production: production, date_and_time: 5.days.ago),
                                      payout_scheme: flat_scheme, calculated_at: Time.current)

      post manage_update_defaults_money_payout_scheme_path(act_scheme),
           params: { production_ids: [ production.id ], effective_from: 1.month.ago.to_date.to_s }

      expect(pending.reload.payout_scheme).to eq(act_scheme)
      expect(calculated.reload.payout_scheme).to eq(flat_scheme)
    end

    it "ignores production ids from another organization" do
      foreign = create(:production, organization: create(:organization))

      post manage_update_defaults_money_payout_scheme_path(act_scheme), params: { production_ids: [ foreign.id ] }

      expect(PayoutSchemeDefault.for_production(foreign)).to be_empty
    end
  end
end
