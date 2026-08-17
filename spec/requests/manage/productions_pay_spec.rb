# frozen_string_literal: true

require "rails_helper"

# The Pay tab on the production edit page: are performers paid for this
# production, and which payout scheme do its shows start from?
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
    it "renders the performer pay card with the org's schemes" do
      get edit_manage_production_path(production)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Performer pay")
      expect(response.body).to include("Performers are paid for this production")
      expect(response.body).to include("Flat Fifty")
      expect(response.body).to include("Act Pay")
      expect(response.body).to include("Manage payout schemes")
      expect(response.body).to include(update_pay_manage_production_path(production))
    end

    it "keeps Danger Zone as the last tab" do
      get edit_manage_production_path(production)

      pay_at = response.body.index('data-index="6"')
      danger_at = response.body.index('data-index="7"')
      expect(pay_at).to be < danger_at
      expect(response.body[danger_at, 200]).to include("Danger Zone")
    end

    it "preselects the production's current default scheme" do
      flat_scheme.add_default_for_production!(production)

      get edit_manage_production_path(production)

      expect(response.body).to include(%(<option value="#{flat_scheme.id}" selected>))
    end

    it "nudges an act-based production toward the Per-Act preset when the org has no per-act scheme" do
      production.update!(casting_mode: "act_based")
      act_scheme.archive!

      get edit_manage_production_path(production)

      expect(response.body).to include("Act-based productions usually pay per act")
      expect(response.body).to include(ERB::Util.html_escape(manage_presets_money_payout_schemes_path(preset: "per_act", production_id: production.id)))
    end

    it "does not nudge when a per-act scheme already exists" do
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
    it "makes the chosen scheme the production's default from today" do
      patch update_pay_manage_production_path(production), params: { performers_paid: "1", payout_scheme_id: flat_scheme.id }

      expect(response).to redirect_to(edit_manage_production_path(production, anchor: "tab-6"))
      default = PayoutSchemeDefault.for_production(production).first
      expect(default.payout_scheme).to eq(flat_scheme)
      expect(default.effective_from).to eq(Date.current)
      expect(PayoutScheme.current_default_for_production(production)).to eq(flat_scheme)
    end

    it "switches schemes without touching the scheme's other productions" do
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

    it "asks for a scheme when paid but none picked" do
      patch update_pay_manage_production_path(production), params: { performers_paid: "1", payout_scheme_id: "" }

      expect(response).to redirect_to(edit_manage_production_path(production, anchor: "tab-6"))
      expect(flash[:alert]).to include("Pick a payout scheme")
      expect(PayoutSchemeDefault.for_production(production)).to be_empty
    end

    it "ignores a scheme from another organization" do
      foreign = PayoutScheme.create!(organization: create(:organization), name: "Not Ours",
                                     rules: { "distribution" => { "method" => "equal" } })

      patch update_pay_manage_production_path(production), params: { performers_paid: "1", payout_scheme_id: foreign.id }

      expect(PayoutSchemeDefault.for_production(production)).to be_empty
    end
  end

  describe "casting nudge helper + partial" do
    include PayoutHelper

    it "nudges an act-based production with no scheme, and stops once one is set" do
      production.update!(casting_mode: "act_based")
      expect(production_needs_per_act_scheme_nudge?(production)).to be(true)

      act_scheme.add_default_for_production!(production)
      expect(production_needs_per_act_scheme_nudge?(production.reload)).to be(false)
    end

    it "never nudges a role-based production" do
      expect(production_needs_per_act_scheme_nudge?(production)).to be(false)
    end

    it "renders the alert panel pointing at the Per-Act preset" do
      production.update!(casting_mode: "act_based")
      html = ApplicationController.render(partial: "manage/casting/pay_scheme_nudge", locals: { production: production })

      expect(html).to include("Pay by act?")
      expect(html).to include("Set up per-act pay")
      expect(html).to include("preset=per_act")
      expect(html).to include("production_id=#{production.id}")
    end
  end
end
