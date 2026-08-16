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
      expect(response.body).to include("2+ acts")
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
  end
end
