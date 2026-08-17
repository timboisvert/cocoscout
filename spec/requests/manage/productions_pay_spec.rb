# frozen_string_literal: true

require "rails_helper"

# The Pay tab on the production edit page: are performers paid for this
# production, and which payout calculation do its shows start from?
RSpec.describe "Manage::Productions Pay tab", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, name: "Friday Variety") }
  let!(:flat_scheme) do
    PayoutScheme.create!(organization: org, name: "Flat Fifty",
                         rules: { "distribution" => { "method" => "flat_fee", "flat_amount" => 50.0 } })
  end
  let!(:act_scheme) do
    PayoutScheme.create!(organization: org, name: "Act Pay",
                         rules: { "distribution" => { "method" => "per_act", "act_mode" => "simple", "per_act_rate" => 25.0 } })
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  describe "the tab" do
    it "renders the performer pay card with the picker modal listing the org's calculations" do
      get edit_manage_production_path(production)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Performer pay")
      expect(response.body).to include("Performers are paid for this production")
      expect(response.body).to include('id="pick-calculation"')
      expect(response.body).to include("Choose a payout calculation")
      expect(response.body).to include("Flat Fifty")
      expect(response.body).to include("Act Pay")
      expect(response.body).to include("No calculation chosen yet")
      expect(response.body).to include("Choose a calculation")
      expect(response.body).to include("Create a new calculation")
      expect(response.body).to include(update_pay_manage_production_path(production))
      expect(response.body).not_to include("payout scheme")
      expect(response.body).not_to include('name="payout_scheme_id" id="payout_scheme_id"')
    end

    it "links both create paths into the calculation wizard for this production, returning to the Pay tab" do
      get edit_manage_production_path(production)

      wizard = ERB::Util.html_escape(manage_money_payout_calculation_wizard_start_path(
        production_id: production.id, return_to: edit_manage_production_path(production, anchor: "tab-6")
      ))
      expect(response.body.scan(wizard).size).to be >= 2
    end

    it "keeps Danger Zone as the last tab" do
      get edit_manage_production_path(production)

      pay_at = response.body.index('data-index="6"')
      danger_at = response.body.index('data-index="7"')
      expect(pay_at).to be < danger_at
      expect(response.body[danger_at, 200]).to include("Danger Zone")
    end

    it "shows the current calculation as a card, tags it in the picker and keeps it on Save" do
      flat_scheme.add_default_for_production!(production)
      show = create(:show, production: production, date_and_time: 2.days.ago)
      ShowPayout.create!(show: show, payout_scheme: flat_scheme)

      get edit_manage_production_path(production)

      expect(response.body).to include("Current calculation")
      expect(response.body).to include("Used by 1 show so far")
      expect(response.body).to include(manage_money_payout_calculation_path(flat_scheme))
      expect(response.body).to include("Choose a different calculation")
      expect(response.body).to match(/<input type="radio" name="payout_scheme_id" value="#{flat_scheme.id}" checked/)
      expect(response.body).to include(">Current<")
      expect(response.body).to match(/<input type="hidden" name="payout_scheme_id" value="#{flat_scheme.id}"/)
    end

    it "nudges an act-based production into the calculation wizard when the org has no per-act calculation" do
      production.update!(casting_mode: "act_based")
      act_scheme.archive!

      get edit_manage_production_path(production)

      expect(response.body).to include("Act-based productions usually pay per act")
      expect(response.body).to include("set up a per-act calculation")
      expect(response.body).not_to include("preset=per_act")
    end

    it "does not nudge when a per-act calculation already exists" do
      production.update!(casting_mode: "act_based")

      get edit_manage_production_path(production)

      expect(response.body).not_to include("Act-based productions usually pay per act")
    end

    context "on the free plan" do
      before { org.update!(comped_indefinitely: false, subscription_status: nil) }

      it "renders the card locked" do
        get edit_manage_production_path(production)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Pro feature")
        expect(response.body).to include("part of CocoScout Pro")
        expect(response.body).to include("Upgrade to Pro")
        expect(response.body).not_to include(update_pay_manage_production_path(production))
      end

      it "refuses to save" do
        patch update_pay_manage_production_path(production), params: { performers_paid: "1", payout_scheme_id: flat_scheme.id }

        expect(response).to redirect_to(edit_manage_production_path(production, anchor: "tab-6"))
        expect(PayoutScheme.current_default_for_production(production)).to be_nil
      end
    end
  end

  describe "saving" do
    it "makes the calculation picked in the modal the production's default from today" do
      patch update_pay_manage_production_path(production), params: { performers_paid: "1", payout_scheme_id: flat_scheme.id }

      expect(response).to redirect_to(edit_manage_production_path(production, anchor: "tab-6"))
      default = PayoutSchemeDefault.for_production(production).first
      expect(default.payout_scheme).to eq(flat_scheme)
      expect(default.effective_from).to eq(Date.current)
      expect(PayoutScheme.current_default_for_production(production)).to eq(flat_scheme)
    end

    it "reaches back to the production's first show, so a night that already happened resolves to it" do
      past_show = create(:show, production: production, date_and_time: 3.weeks.ago)
      create(:show, production: production, date_and_time: 1.week.from_now)

      patch update_pay_manage_production_path(production), params: { performers_paid: "1", payout_scheme_id: act_scheme.id }

      default = PayoutSchemeDefault.for_production(production).first
      expect(default.effective_from).to eq(3.weeks.ago.to_date)
      expect(PayoutScheme.default_for_show(past_show)).to eq(act_scheme)
    end

    it "restamps payouts nobody has calculated yet, so the choice sticks on the payout page" do
      # An earlier visit pinned this show's payout to the org fallback...
      show = create(:show, production: production, date_and_time: 2.days.ago)
      pending = ShowPayout.create!(show: show, payout_scheme: flat_scheme)
      # ...while a calculated show, and one with a hand-tuned override, keep theirs.
      calculated = ShowPayout.create!(show: create(:show, production: production, date_and_time: 5.days.ago),
                                      payout_scheme: flat_scheme, calculated_at: Time.current)
      overridden = ShowPayout.create!(show: create(:show, production: production, date_and_time: 4.days.ago),
                                      payout_scheme: flat_scheme, override_rules: { "distribution" => { "method" => "flat_fee", "flat_amount" => 10 } })

      patch update_pay_manage_production_path(production), params: { performers_paid: "1", payout_scheme_id: act_scheme.id }

      expect(pending.reload.payout_scheme).to eq(act_scheme)
      expect(calculated.reload.payout_scheme).to eq(flat_scheme)
      expect(overridden.reload.payout_scheme).to eq(flat_scheme)

      get manage_money_show_payout_path(show)
      expect(response.body).to include("Act Pay")
    end

    it "shows the Pro pill and the current calculation's summary" do
      act_scheme.make_production_scheme!(production)

      get edit_manage_production_path(production)
      expect(response.body).to include("Pro feature")
      expect(response.body).to include("Current calculation")
      expect(response.body).to include(act_scheme.rules_summary)
    end

    it "switches calculations without touching the calculation's other productions" do
      other = create(:production, organization: org, name: "Saturday Cabaret")
      flat_scheme.add_default_for_production!(production)
      flat_scheme.add_default_for_production!(other)

      patch update_pay_manage_production_path(production), params: { performers_paid: "1", payout_scheme_id: act_scheme.id }

      expect(PayoutScheme.current_default_for_production(production)).to eq(act_scheme)
      expect(PayoutScheme.current_default_for_production(other)).to eq(flat_scheme)
    end

    it "removes the production's defaults when performers aren't paid" do
      flat_scheme.add_default_for_production!(production)

      patch update_pay_manage_production_path(production), params: { performers_paid: "0" }

      expect(response).to redirect_to(edit_manage_production_path(production, anchor: "tab-6"))
      expect(PayoutSchemeDefault.for_production(production)).to be_empty
    end

    it "asks for a calculation when paid but none picked" do
      patch update_pay_manage_production_path(production), params: { performers_paid: "1", payout_scheme_id: "" }

      expect(response).to redirect_to(edit_manage_production_path(production, anchor: "tab-6"))
      expect(flash[:alert]).to include("Choose a payout calculation")
      expect(PayoutSchemeDefault.for_production(production)).to be_empty
    end

    it "ignores a calculation from another organization" do
      foreign = PayoutScheme.create!(organization: create(:organization), name: "Not Ours",
                                     rules: { "distribution" => { "method" => "equal" } })

      patch update_pay_manage_production_path(production), params: { performers_paid: "1", payout_scheme_id: foreign.id }

      expect(PayoutSchemeDefault.for_production(production)).to be_empty
    end
  end

  describe "casting nudge helper + partial" do
    include PayoutHelper

    it "nudges an act-based production with no calculation, and stops once one is set" do
      production.update!(casting_mode: "act_based")
      expect(production_needs_per_act_calculation_nudge?(production)).to be(true)

      act_scheme.add_default_for_production!(production)
      expect(production_needs_per_act_calculation_nudge?(production.reload)).to be(false)
    end

    it "never nudges a role-based production" do
      expect(production_needs_per_act_calculation_nudge?(production)).to be(false)
    end

    it "renders the alert panel pointing into the calculation wizard, coming back to casting" do
      production.update!(casting_mode: "act_based")
      html = ApplicationController.render(partial: "manage/casting/pay_calculation_nudge", locals: { production: production })

      expect(html).to include("Pay by act?")
      expect(html).to include("Set up per-act pay")
      expect(html).to include("payout calculation")
      expect(html).not_to include("preset=per_act")
      expect(html).to include(ERB::Util.html_escape(manage_money_payout_calculation_wizard_start_path(
        production_id: production.id, return_to: manage_casting_production_path(production)
      )))
    end
  end
end
