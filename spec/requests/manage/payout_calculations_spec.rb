# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::PayoutCalculations", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, name: "Friday Cabaret") }

  let!(:flat_calculation) do
    PayoutScheme.create!(organization: org, name: "Flat Fifty",
                         rules: { "distribution" => { "method" => "flat_fee", "flat_amount" => 50.0 } })
  end
  let!(:act_calculation) do
    PayoutScheme.create!(organization: org, name: "Act Pay",
                         rules: { "distribution" => { "method" => "per_act", "act_mode" => "simple", "per_act_rate" => 25.0 } })
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  # What a person reads on the page — no importmap/script names.
  def visible_text
    Nokogiri::HTML(response.body).tap { |doc| doc.css("script, style").remove }.text
  end

  describe "the list" do
    it "lists every calculation with a New calculation button and no scheme wording" do
      get manage_money_payout_calculations_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Payout Calculations")
      expect(response.body).to include("New calculation")
      expect(response.body).to include(manage_money_payout_calculation_wizard_start_path)
      expect(response.body).to include("Flat Fifty")
      expect(response.body).to include("Act Pay")
      expect(response.body).to include("$25.00 per act")
      expect(visible_text).not_to match(/scheme/i)
    end

    it "lays the calculations out as cards that say which productions use each one" do
      other = create(:production, organization: org, name: "Sunday Sketch")
      act_calculation.make_production_scheme!(production)
      act_calculation.make_production_scheme!(other)

      get manage_money_payout_calculations_path

      expect(response.body).to include("Used by")
      expect(response.body).to include("Friday Cabaret and Sunday Sketch")
      expect(response.body).to include("Not used by any production yet") # the flat one
      expect(response.body).to include("Per act") # approach pill
      expect(response.body).to include("grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3")
      expect(response.body).not_to include("Organization default")
      expect(response.body).not_to include("legacy")
    end

    it "keeps archived calculations behind a toggle with a Restore button" do
      act_calculation.archive!

      get manage_money_payout_calculations_path
      expect(response.body).not_to include("Act Pay")
      expect(response.body).to include("View 1 archived calculation")

      get manage_money_payout_calculations_path(archived: 1)
      expect(response.body).to include("Act Pay")
      expect(response.body).to include("Restore")
      expect(response.body).to include(manage_unarchive_money_payout_calculation_path(act_calculation))
    end

    it "explains what a calculation is when there are none" do
      PayoutScheme.where(organization: org).destroy_all

      get manage_money_payout_calculations_path

      expect(response.body).to include("No payout calculations yet")
      expect(response.body).to include("New calculation")
    end
  end

  describe "a calculation's page" do
    it "spells out how it works, who uses it, and offers the used-by modal" do
      act_calculation.make_production_scheme!(production)

      get manage_money_payout_calculation_path(act_calculation)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("How it works")
      expect(response.body).to include("$25.00 per act")
      expect(response.body).to include("Used by")
      expect(response.body).to include("Friday Cabaret")
      expect(response.body).to match(/name="production_ids\[\]" value="#{production.id}"\s+checked/)
      expect(response.body).not_to include('name="org_level_fallback"')
      expect(response.body).not_to include("Organization default")
      expect(response.body).not_to include('name="effective_from"')
      expect(response.body).to include(manage_update_defaults_money_payout_calculation_path(act_calculation))
      expect(visible_text).not_to match(/scheme/i)
    end

    it "offers Edit, Duplicate, Archive and Delete" do
      get manage_money_payout_calculation_path(act_calculation)

      expect(response.body).to include(manage_money_payout_calculation_wizard_start_path(id: act_calculation))
      expect(response.body).to include(ERB::Util.html_escape(manage_money_payout_calculation_wizard_start_path(id: act_calculation, duplicate: 1)))
      expect(response.body).to include(manage_archive_money_payout_calculation_path(act_calculation))
      expect(response.body).to include("Delete this calculation?")
    end

    it "spells out tiered act rules" do
      tiered = PayoutScheme.create!(
        organization: org, name: "Tiered Act Pay",
        rules: { "distribution" => { "method" => "per_act", "act_mode" => "tiers",
                                     "tiers" => [ { "acts" => 1, "amount" => 25.0 }, { "acts" => 2, "amount" => 50.0 } ] } }
      )

      get manage_money_payout_calculation_path(tiered)

      expect(response.body).to include("1 act $25.00, 2+ acts $50.00")
    end

    it "says performers aren't paid under a no-pay calculation" do
      no_pay = PayoutScheme.create!(organization: org, name: "Rehearsal", rules: { "distribution" => { "method" => "no_pay" } })

      get manage_money_payout_calculation_path(no_pay)

      expect(response.body).to include("Performers aren&#39;t paid")
    end

    it "notes leftover per-person exceptions" do
      person = create(:person)
      act_calculation.update!(rules: act_calculation.rules.merge(
        "performer_overrides" => { person.id.to_s => { "per_act_rate" => 35.0 } }
      ))

      get manage_money_payout_calculation_path(act_calculation)

      expect(response.body).to include("carries per-person exceptions from before")
    end

    it "does not show another organization's calculation" do
      foreign = PayoutScheme.create!(organization: create(:organization), name: "Not Ours",
                                     rules: { "distribution" => { "method" => "equal" } })

      get manage_money_payout_calculation_path(foreign)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "editing who uses a calculation" do
    let!(:other) { create(:production, organization: org, name: "Sunday Sketch") }

    it "makes it the production calculation for checked productions" do
      post manage_update_defaults_money_payout_calculation_path(act_calculation), params: { production_ids: [ production.id ] }

      expect(response).to redirect_to(manage_money_payout_calculation_path(act_calculation))
      expect(PayoutScheme.current_default_for_production(production)).to eq(act_calculation)
      expect(PayoutScheme.current_default_for_production(other)).to be_nil
      expect(flash[:notice]).to include("Friday Cabaret")
    end

    it "clears productions that were unchecked so they fall back to the organization default" do
      act_calculation.make_production_scheme!(production)
      act_calculation.make_production_scheme!(other)

      post manage_update_defaults_money_payout_calculation_path(act_calculation), params: { production_ids: [ other.id ] }

      expect(PayoutScheme.current_default_for_production(production)).to be_nil
      expect(PayoutScheme.current_default_for_production(other)).to eq(act_calculation)
    end

    it "takes over a production from another calculation" do
      flat_calculation.make_production_scheme!(production)

      post manage_update_defaults_money_payout_calculation_path(act_calculation), params: { production_ids: [ production.id ] }

      expect(PayoutScheme.current_default_for_production(production)).to eq(act_calculation)
      expect(flat_calculation.reload.default_for_production?(production)).to be(false)
    end

    it "restamps payouts nobody has calculated yet, and leaves calculated ones alone" do
      show = create(:show, production: production, date_and_time: 2.days.ago)
      pending = ShowPayout.create!(show: show, payout_scheme: flat_calculation)
      calculated = ShowPayout.create!(show: create(:show, production: production, date_and_time: 5.days.ago),
                                      payout_scheme: flat_calculation, calculated_at: Time.current)

      post manage_update_defaults_money_payout_calculation_path(act_calculation), params: { production_ids: [ production.id ] }

      expect(pending.reload.payout_scheme).to eq(act_calculation)
      expect(calculated.reload.payout_scheme).to eq(flat_calculation)
    end

    it "ignores production ids from another organization" do
      foreign = create(:production, organization: create(:organization))

      post manage_update_defaults_money_payout_calculation_path(act_calculation), params: { production_ids: [ foreign.id ] }

      expect(PayoutSchemeDefault.for_production(foreign)).to be_empty
    end
  end

  describe "archiving and deleting" do
    it "archives and restores" do
      post manage_archive_money_payout_calculation_path(act_calculation)
      expect(response).to redirect_to(manage_money_payout_calculations_path)
      expect(act_calculation.reload).to be_archived

      post manage_unarchive_money_payout_calculation_path(act_calculation)
      expect(response).to redirect_to(manage_money_payout_calculation_path(act_calculation))
      expect(act_calculation.reload).not_to be_archived
    end

    it "deletes a calculation nobody has been paid under" do
      delete manage_money_payout_calculation_path(act_calculation)

      expect(response).to redirect_to(manage_money_payout_calculations_path)
      expect(PayoutScheme.exists?(act_calculation.id)).to be(false)
    end

    it "refuses to delete a calculation people have been paid under" do
      show = create(:show, production: production, date_and_time: 2.days.ago)
      ShowPayout.create!(show: show, payout_scheme: act_calculation, status: "paid", calculated_at: Time.current)

      delete manage_money_payout_calculation_path(act_calculation)

      expect(response).to redirect_to(manage_money_payout_calculations_path)
      expect(flash[:alert]).to include("archive it instead")
      expect(PayoutScheme.exists?(act_calculation.id)).to be(true)
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

    it "pays the top tier above the table when there is no beyond rate" do
      expect(PayoutScheme.act_amount(tiered, 9)).to eq(50.0)
      expect(PayoutScheme.act_rules_description(tiered)).to eq("1 act $25.00, 2+ acts $50.00")
    end

    it "adds the beyond rate for every act past the last row" do
      beyond = tiered.merge("additional_act_rate" => 15.0)
      expect(PayoutScheme.act_amount(beyond, 2)).to eq(50.0)
      expect(PayoutScheme.act_amount(beyond, 3)).to eq(65.0)
      expect(PayoutScheme.act_amount(beyond, 5)).to eq(95.0)
      expect(PayoutScheme.act_rules_description(beyond)).to eq("1 act $25.00, 2 acts $50.00, then $15.00 per act")
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
end
