# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::ShowPayouts", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }
  let!(:show) { create(:show, production: production, event_type: :show, date_and_time: 3.days.ago) }
  let!(:financials) { create(:show_financials, :complete, show: show, ticket_revenue: 500) }
  let!(:payout) { ShowPayout.create!(show: show, status: "awaiting_payout", calculated_at: Time.current, total_payout: 180) }
  let!(:li_paid) do
    ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person, name: "Paid Pat"), amount: 60)
      .tap { |li| li.update_columns(manually_paid: true) }
  end
  let!(:li_unpaid) do
    ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person, name: "Owed Ollie", stripe_account_id: "acct_1", payouts_enabled: true), amount: 120)
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "shows the payout amounts as at-a-glance boxes" do
    get manage_money_show_payout_path(show)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Total payout")
    expect(response.body).to include("$180.00")     # full net payout
    expect(response.body).to include("Already paid")
    expect(response.body).to include("$60.00")      # what's already been paid
  end

  it "offers an add-to-run preview modal instead of a confirm alert" do
    get manage_money_show_payout_path(show)
    expect(response.body).to include("add-to-run-modal")
    expect(response.body).to include("Owed Ollie")            # eligible unpaid performer listed
    expect(response.body).not_to include("turbo_confirm=\"Add these performer payouts")
  end

  it "stays on the payout page after adding to the run (doesn't jump to the batch)" do
    post manage_add_to_run_money_show_payout_path(show)
    expect(response).to redirect_to(manage_money_show_payout_path(show))
  end

  it "adds no-bank payees to the run too — their money rides it until they connect" do
    nobank = ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person, name: "Nobank Nel"), amount: 30)

    post manage_add_to_run_money_show_payout_path(show)

    expect(nobank.reload.in_payout_run?).to be(true)
    expect(li_unpaid.reload.in_payout_run?).to be(true)

    get manage_money_show_payout_path(show)
    expect(response.body).to include("awaiting their bank")
  end

  it "still offers Add to payout run for a line that missed the first add (e.g. a producer allocation)" do
    producer = ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person, name: "Gib Producer"),
                                          amount: 29.30, is_individual_allocation: true)
    # First add stages only Ollie (picker selection) — the show is now "in a run".
    post manage_add_to_run_money_show_payout_path(show), params: { line_item_ids: [ li_unpaid.id ] }
    expect(producer.reload.in_payout_run?).to be(false)

    # The page must still offer to stage the leftover line…
    get manage_money_show_payout_path(show)
    expect(response.body).to include("Add to payout run")
    expect(response.body).to include("Gib Producer")

    # …and adding again picks him up.
    post manage_add_to_run_money_show_payout_path(show)
    expect(producer.reload.in_payout_run?).to be(true)
  end

  it "only adds the picker's checked lines; unchecked people stay off the run" do
    nobank = ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person, name: "Nobank Nel"), amount: 30)

    post manage_add_to_run_money_show_payout_path(show), params: { line_item_ids: [ li_unpaid.id ] }

    expect(li_unpaid.reload.in_payout_run?).to be(true)
    expect(nobank.reload.in_payout_run?).to be(false)
  end

  describe "the Payout calculation card" do
    let!(:cast_role) { create(:role, production: production) }
    let!(:jane) { create(:person, name: "Jane Doe") }
    let!(:jack) { create(:person, name: "Jack Sprat") }
    let!(:jane_cast) { create(:show_person_role_assignment, show: show, role: cast_role, assignable: jane) }
    let!(:jack_cast) { create(:show_person_role_assignment, show: show, role: cast_role, assignable: jack) }
    let!(:gigi_cast) { create(:show_person_role_assignment, show: show, role: cast_role, guest_name: "Gigi Guest", assignable: nil) }
    let!(:house_split) do
      PayoutScheme.create!(
        organization: org, name: "House Split",
        rules: {
          "allocation" => [ { "type" => "percentage", "value" => 40.0, "label" => "House take" }, { "type" => "remainder", "label" => "Performer pool" } ],
          "distribution" => { "method" => "shares", "default_shares" => 1.0 },
          "performer_overrides" => {}
        }
      )
    end
    let!(:flat_fifty) do
      PayoutScheme.create!(organization: org, name: "Flat Fifty",
                           rules: { "allocation" => [], "distribution" => { "method" => "flat_fee", "flat_amount" => 50.0 }, "performer_overrides" => {} })
    end

    before do
      financials.update!(ticket_count: 100, ticket_revenue: 1000, expenses: 0)
      payout.line_items.destroy_all
      payout.update!(calculated_at: nil, total_payout: nil)
    end

    context "when the show uses the production's calculation" do
      before do
        house_split.make_production_scheme!(production)
        payout.update!(payout_scheme: house_split)
      end

      it "names the calculation and offers to customize or choose another — never where it came from" do
        get manage_money_show_payout_path(show)

        expect(response.body).to include("Payout calculation")
        expect(response.body).to include("House Split")
        expect(response.body).not_to include("Inherited")
        expect(response.body).not_to include("inherited")
        expect(response.body).not_to include("All calculations")
        expect(response.body).not_to include("Manage calculations")
        expect(response.body).not_to include("tonight")
        expect(response.body).not_to include("Tonight")
        expect(response.body).to include("Customize for this event")
        expect(response.body).to include("Choose a different calculation")
        expect(response.body).not_to include("Back to the production")
        expect(response.body).not_to include("Payout Scheme")
      end

      it "picks a different calculation for just this show, and offers the way back" do
        later = create(:show, production: production, event_type: :show, date_and_time: 3.days.from_now)
        later_payout = ShowPayout.create!(show: later, status: "awaiting_payout", payout_scheme: house_split)

        get manage_money_show_payout_path(show)
        expect(response.body).to include("choose-calculation")
        expect(response.body).to include("1 later show uses the same calculation")

        patch manage_apply_choice_money_show_payout_path(show), params: { payout_scheme_id: flat_fifty.id, apply_to_future: "0" }

        expect(response).to redirect_to(manage_money_show_payout_path(show))
        expect(payout.reload.payout_scheme).to eq(flat_fifty)
        expect(later_payout.reload.payout_scheme).to eq(house_split)
        follow_redirect!
        expect(response.body).to include("Flat Fifty")
        expect(response.body).to include("Back to the production&#39;s calculation")
      end

      it "carries the choice to this show and every later show still on the same calculation" do
        later = create(:show, production: production, event_type: :show, date_and_time: 3.days.from_now)
        later_payout = ShowPayout.create!(show: later, status: "awaiting_payout", payout_scheme: house_split)
        other = create(:show, production: production, event_type: :show, date_and_time: 5.days.from_now)
        other_payout = ShowPayout.create!(show: other, status: "awaiting_payout", payout_scheme: flat_fifty)

        patch manage_apply_choice_money_show_payout_path(show), params: { payout_scheme_id: flat_fifty.id, apply_to_future: "1" }

        expect(payout.reload.payout_scheme).to eq(flat_fifty)
        expect(later_payout.reload.payout_scheme).to eq(flat_fifty)
        expect(other_payout.reload.payout_scheme).to eq(flat_fifty)
        expect(flash[:notice]).to include("2 shows")
      end

      it "hides Choose and Back while customized — only edit or remove the customization" do
        payout.update!(payout_scheme: flat_fifty, override_rules: { "distribution" => { "method" => "flat_fee", "flat_amount" => 60.0 } })

        get manage_money_show_payout_path(show)
        expect(response.body).to include("Edit customization")
        expect(response.body).to include("Remove customization")
        expect(response.body).not_to include("Choose a different calculation")
        expect(response.body).not_to include("Back to the production")

        delete manage_clear_override_money_show_payout_path(show)
        get manage_money_show_payout_path(show)
        expect(response.body).to include("Choose a different calculation")
        expect(response.body).to include("Back to the production")
      end

      it "goes back to the production's calculation and drops the customization" do
        payout.update!(payout_scheme: flat_fifty, override_rules: { "distribution" => { "method" => "flat_fee", "flat_amount" => 60.0 } })

        patch manage_use_default_money_show_payout_path(show)

        expect(response).to redirect_to(manage_money_show_payout_path(show))
        payout.reload
        expect(payout.payout_scheme).to eq(house_split)
        expect(payout.override_rules).to be_nil
      end

      describe "the Customize modal" do
        it "offers the two ways to pay this event, and nothing of the old amounts form" do
          get manage_money_show_payout_path(show)

          expect(response.body).to include("Customize this event's calculation")
          expect(response.body).to include("Pay everyone the same amount")
          expect(response.body).to include("Pay people different amounts")
          expect(response.body).to include(%(name="customize[amount]"))
          expect(response.body).to include(%(name="customize[amounts][Person_#{jane.id}]"))
          expect(response.body).to include(%(name="customize[amounts][guest_#{gigi_cast.id}]"))
          expect(response.body).not_to include("house_percentage")
          expect(response.body).not_to include("expenses_first")
          expect(response.body).not_to include("As calculated")
          expect(response.body).not_to include("Adjust the amounts</h4>")
        end

        it "prefills each person with a dry run of the calculation when nothing's been calculated yet — and leaves nothing behind" do
          get manage_money_show_payout_path(show)

          # 60% of $1000 split three ways
          expect(response.body).to include(%(name="customize[amounts][Person_#{jane.id}]" value="200.00"))
          expect(response.body).to include(%(name="customize[amounts][Person_#{jack.id}]" value="200.00"))
          expect(response.body).to include(%(name="customize[amounts][guest_#{gigi_cast.id}]" value="200.00"))
          expect(response.body).to include("calculated $600.00")
          expect(response.body).to include(%(data-payout-customize-fixed-pot-value="true"))

          payout.reload
          expect(payout.line_items).to be_empty
          expect(payout.calculated_at).to be_nil
          expect(payout.total_payout).to be_nil
          expect(PayoutLedgerEntry.where(payee: jane)).to be_empty
        end

        it "prefills each person with their calculated line when the payout has been calculated" do
          payout.line_items.create!(payee: jane, amount: 111)
          payout.line_items.create!(payee: jack, amount: 222)
          payout.line_items.create!(is_guest: true, guest_name: "Gigi Guest", amount: 267)
          payout.update!(calculated_at: Time.current, total_payout: 600)

          get manage_money_show_payout_path(show)

          expect(response.body).to include(%(name="customize[amounts][Person_#{jane.id}]" value="111.00"))
          expect(response.body).to include(%(name="customize[amounts][Person_#{jack.id}]" value="222.00"))
          expect(response.body).to include(%(name="customize[amounts][guest_#{gigi_cast.id}]" value="267.00"))
        end

        it "reopens on the last customization, prefilled with its amounts" do
          payout.update!(override_rules: PayoutRulesBuilder.override(house_split.rules, performer_overrides: { jane.id.to_s => { flat_amount: "75" } }))

          get manage_money_show_payout_path(show)

          expect(response.body).to include(%(name="customize[mode]" value="different" checked))
          expect(response.body).to include(%(name="customize[amounts][Person_#{jane.id}]" value="75.00"))
        end
      end

      describe "saving a customization" do
        it "pays everyone the same amount" do
          patch manage_save_override_money_show_payout_path(show), params: { customize: { mode: "same", amount: "60" } }

          expect(response).to redirect_to(manage_money_show_payout_path(show))
          rules = payout.reload.override_rules
          expect(rules["distribution"]).to eq("method" => "flat_fee", "flat_amount" => 60.0)
          expect(rules["allocation"]).to eq([])
          expect(rules["performer_overrides"]).to eq({})
          expect(payout.customization_summary).to eq("Everyone $60")

          follow_redirect!
          expect(response.body).to include("Customized for this event")
          expect(response.body).to include("Everyone $60")
          expect(response.body).to include("Edit customization").and include("Remove customization")
          expect(response.body).not_to include("Inherited")
        end

        it "won't split a fixed pot into amounts that don't add up to it" do
          patch manage_save_override_money_show_payout_path(show),
                params: { customize: { mode: "different", amounts: { "Person_#{jane.id}" => "100", "Person_#{jack.id}" => "100", "guest_#{gigi_cast.id}" => "100" } } }

          expect(response).to redirect_to(manage_money_show_payout_path(show))
          expect(flash[:alert]).to include("add up to $600.00")
          expect(payout.reload.override_rules).to be_nil
        end

        it "pays people different amounts that do add up to the pot, guests included, and the calculation honours them" do
          patch manage_save_override_money_show_payout_path(show),
                params: { customize: { mode: "different", amounts: { "Person_#{jane.id}" => "300", "Person_#{jack.id}" => "200", "guest_#{gigi_cast.id}" => "100" } } }

          expect(response).to redirect_to(manage_money_show_payout_path(show))
          rules = payout.reload.override_rules
          expect(rules.dig("distribution", "method")).to eq("shares")
          expect(rules["allocation"]).to include(a_hash_including("type" => "percentage", "value" => 40.0))
          expect(rules["performer_overrides"]).to eq(
            jane.id.to_s => { "flat_amount" => 300.0 }, jack.id.to_s => { "flat_amount" => 200.0 }, "guest_#{gigi_cast.id}" => { "flat_amount" => 100.0 }
          )

          get manage_money_show_payout_path(show)
          expect(response.body).to include("Jane Doe $300, Jack Sprat $200, Gigi Guest (guest) $100")

          post manage_calculate_money_show_payout_path(show)
          expect(payout.line_items.find_by(payee: jane).amount.to_f).to eq(300.0)
          expect(payout.line_items.find_by(payee: jane).calculation_details["formula"]).to eq("Custom amount")
          expect(payout.line_items.find_by(payee: jack).amount.to_f).to eq(200.0)
          expect(payout.line_items.find_by(is_guest: true, guest_name: "Gigi Guest").amount.to_f).to eq(100.0)
        end

        it "lets the amounts differ from the calculation when nothing is being split" do
          payout.update!(payout_scheme: flat_fifty)

          patch manage_save_override_money_show_payout_path(show),
                params: { customize: { mode: "different", amounts: { "Person_#{jane.id}" => "100", "Person_#{jack.id}" => "50", "guest_#{gigi_cast.id}" => "50" } } }

          expect(flash[:alert]).to be_nil
          expect(payout.reload.override_rules["performer_overrides"]).to include(jane.id.to_s => { "flat_amount" => 100.0 })
        end

        it "recalculates an already-calculated payout so the lines reflect it" do
          post manage_calculate_money_show_payout_path(show)
          expect(payout.reload.calculated_at).to be_present
          expect(payout.line_items.find_by(payee: jane).amount.to_f).to eq(200.0)

          patch manage_save_override_money_show_payout_path(show), params: { customize: { mode: "same", amount: "60" } }

          expect(flash[:notice]).to include("recalculated").and include("$180.00")
          payout.reload
          expect(payout.calculated_at).to be_present
          expect(payout.total_payout.to_f).to eq(180.0)
          expect(payout.line_items.map { |li| li.amount.to_f }).to all(eq(60.0))
        end

        it "always starts over from the calculation, never from the last customization" do
          payout.update!(override_rules: PayoutRulesBuilder.same_amount(house_split.rules, 60))

          patch manage_save_override_money_show_payout_path(show),
                params: { customize: { mode: "different", amounts: { "Person_#{jane.id}" => "300", "Person_#{jack.id}" => "200", "guest_#{gigi_cast.id}" => "100" } } }

          rules = payout.reload.override_rules
          expect(rules.dig("distribution", "method")).to eq("shares")
          expect(rules["allocation"]).to include(a_hash_including("type" => "percentage", "value" => 40.0))
        end

        it "removes the customization" do
          payout.update!(override_rules: { "distribution" => { "method" => "flat_fee", "flat_amount" => 60.0 } })

          delete manage_clear_override_money_show_payout_path(show)

          expect(response).to redirect_to(manage_money_show_payout_path(show))
          expect(payout.reload.override_rules).to be_nil
          expect(flash[:notice]).to include("Customization removed")
        end
      end
    end

    context "when a calculation was chosen for this show and the production has none" do
      before { payout.update!(payout_scheme: house_split) }

      it "just names the calculation — there's nothing to go back to" do
        get manage_money_show_payout_path(show)
        expect(response.body).to include("House Split")
        expect(response.body).to include("Customize for this event")
        expect(response.body).not_to include("Inherited")
        expect(response.body).not_to include("organization's default")
        expect(response.body).not_to include("Back to the production")
      end
    end

    context "when no calculation resolves" do
      before { payout.update!(payout_scheme: nil) }

      it "offers the picker with a create link" do
        get manage_money_show_payout_path(show)

        expect(response.body).to include("doesn't have a payout calculation yet")
        expect(response.body).to include("Choose a calculation")
        expect(response.body).to include("choose-calculation")
        expect(response.body).to include("Create a new calculation")
        expect(response.body).to include(CGI.escapeHTML(manage_money_payout_calculation_wizard_start_path(production_id: production.id, return_to: manage_money_show_payout_path(show))))
        expect(response.body).not_to include("customize-calculation")
      end

      it "won't customize what isn't there" do
        patch manage_save_override_money_show_payout_path(show), params: { customize: { mode: "same", amount: "10" } }
        expect(payout.reload.override_rules).to be_nil
        expect(flash[:alert]).to include("Choose a payout calculation")
      end
    end
  end

  describe "an act-based payout calculation" do
    let!(:role) { create(:role, production: production) }
    let!(:performer) { create(:person, name: "Acty Ada") }
    let!(:assignment) { create(:show_person_role_assignment, show: show, role: role, assignable: performer) }
    let!(:scheme) do
      PayoutScheme.create!(
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
    end

    before { payout.update!(payout_scheme: scheme, calculated_at: nil) }

    it "asks how many acts instead of calculating blind" do
      post manage_calculate_money_show_payout_path(show)

      expect(response).to redirect_to(manage_money_show_payout_path(show, enter_acts: 1))
      expect(payout.reload.calculated_at).to be_nil
    end

    it "opens the acts modal on the page it bounced back to" do
      get manage_money_show_payout_path(show, enter_acts: 1)

      expect(response.body).to include("How many acts?")
      expect(response.body).to include("Acty Ada")
      expect(response.body).to include("act_counts[Person_#{performer.id}]")
    end

    it "calculates from the submitted counts and remembers them" do
      post manage_calculate_money_show_payout_path(show),
           params: { act_counts: { "Person_#{performer.id}" => "2" } }

      expect(response).to redirect_to(manage_money_show_payout_path(show))
      expect(payout.reload.act_counts).to eq("Person_#{performer.id}" => 2)
      expect(payout.line_items.find_by(payee: performer).amount.to_f).to eq(50.0)
    end

    context "when each act has its own rate" do
      before do
        scheme.update!(rules: {
          "distribution" => {
            "method" => "per_act",
            "act_mode" => "schedule",
            "act_rates" => [ { "act" => 1, "amount" => 75.0 }, { "act" => 2, "amount" => 50.0 } ],
            "additional_act_rate" => 25.0
          }
        })
      end

      it "spells the schedule out in the modal" do
        get manage_money_show_payout_path(show, enter_acts: 1)

        expect(response.body).to include("1st act $75.00, 2nd act $50.00, then $25.00 each")
        expect(response.body).to include("Each act is paid at its own rate and they add up.")
      end

      it "adds the acts up when it calculates" do
        post manage_calculate_money_show_payout_path(show),
             params: { act_counts: { "Person_#{performer.id}" => "2" } }

        expect(payout.line_items.find_by(payee: performer).amount.to_f).to eq(125.0)
      end
    end

    it "prefills the modal with the counts entered last time" do
      post manage_calculate_money_show_payout_path(show),
           params: { act_counts: { "Person_#{performer.id}" => "2" } }

      get manage_money_show_payout_path(show, enter_acts: 1)

      expect(response.body).to include(%(name="act_counts[Person_#{performer.id}]" value="2"))
    end

    it "sends a show with no calculation to the production's payouts page, where one is chosen" do
      payout.update!(payout_scheme: nil)
      scheme.destroy!

      post manage_calculate_money_show_payout_path(show)

      expect(response).to redirect_to(manage_money_production_payouts_path(production))
      expect(flash[:alert]).to include("performers are paid first")
    end

    context "in an act-based production (acts are roles in the lineup)" do
      let!(:role) { create(:role, production: production, name: "Opening Magic") }
      let!(:second_role) { create(:role, production: production, name: "Closing Magic") }
      let!(:second_assignment) { create(:show_person_role_assignment, show: show, role: second_role, assignable: performer) }
      let!(:guest_one) { create(:show_person_role_assignment, show: show, role: role, guest_name: "Gigi Guest", assignable: nil) }
      let!(:guest_two) { create(:show_person_role_assignment, show: show, role: second_role, guest_name: "Gigi Guest", assignable: nil) }

      before { production.update!(casting_mode: "act_based") }

      it "calculates straight from the lineup instead of asking for counts" do
        post manage_calculate_money_show_payout_path(show)

        expect(response).to redirect_to(manage_money_show_payout_path(show))
        payout.reload
        expect(payout.calculated_at).to be_present
        expect(payout.act_counts).to eq(
          "Person_#{performer.id}" => 2,
          "guest_#{guest_one.id}" => 2
        )
        expect(payout.line_items.find_by(payee: performer).amount.to_f).to eq(50.0)
        guest_lines = payout.line_items.where(is_guest: true)
        expect(guest_lines.count).to eq(1)
        expect(guest_lines.first.amount.to_f).to eq(50.0)
      end

      it "works out per-act pay before any ticket numbers are entered" do
        financials.destroy!
        payout.line_items.destroy_all

        post manage_calculate_money_show_payout_path(show)

        expect(response).to redirect_to(manage_money_show_payout_path(show))
        expect(payout.reload.calculated_at).to be_present
        expect(payout.line_items.find_by(payee: performer).amount.to_f).to eq(50.0)

        get manage_money_show_payout_path(show)
        expect(response.body).to include("Financial data not entered yet")
        expect(response.body).not_to include("Financial data needed")
      end

      it "still honours counts adjusted by hand" do
        post manage_calculate_money_show_payout_path(show),
             params: { act_counts: { "Person_#{performer.id}" => "1", "guest_#{guest_one.id}" => "2" } }

        expect(payout.reload.act_counts["Person_#{performer.id}"]).to eq(1)
        expect(payout.line_items.find_by(payee: performer).amount.to_f).to eq(25.0)
      end

      it "offers to adjust the act counts and prefills them from the lineup" do
        get manage_money_show_payout_path(show)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Adjust act counts")
        expect(response.body).to include("Reset to lineup")
        expect(response.body).to include("Counted from the lineup — 2 acts")
        expect(response.body).to include(%(name="act_counts[Person_#{performer.id}]" value="2"))
        expect(response.body).to include(%(data-lineup-count="2"))
      end

      it "labels each calculated line as counted from the lineup" do
        post manage_calculate_money_show_payout_path(show)
        get manage_money_show_payout_path(show)

        expect(response.body).to include("2 acts (from lineup)")
      end

      it "sends a show with no calculation to the production's payouts page too" do
        payout.update!(payout_scheme: nil)
        scheme.destroy!

        post manage_calculate_money_show_payout_path(show)

        expect(response).to redirect_to(manage_money_production_payouts_path(production))
      end
    end
  end

  describe "marking an in-run line paid another way" do
    before { org.update!(enabled_offline_payout_methods: [ "cash" ]) }

    it "on a DRAFT run: records the payment and removes them — no credit minted" do
      nobank = ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person, name: "Nobank Nel"), amount: 30)
      post manage_add_to_run_money_show_payout_path(show)
      expect(nobank.reload.in_payout_run?).to be(true)

      post manage_mark_line_item_paid_money_show_payout_path(show, nobank), params: { payment_method: "cash" }

      nobank.reload
      expect(nobank.manually_paid).to be(true)
      expect(nobank.in_payout_run?).to be(false)
      expect(PayoutFundingCredit.count).to eq(0)
    end

    it "on a FUNDED run: records the payment, releases them, and mints funding credit" do
      org.update!(stripe_customer_id: "cus_1", funding_payment_method_id: "pm_1", funding_payment_method_type: "us_bank_account")
      allow(Stripe::PaymentIntent).to receive(:create).and_return(double("pi", id: "pi_1", status: "succeeded", amount: 5000))
      allow(Stripe::Transfer).to receive(:create).and_return(double("tr", id: "tr_1"))

      nobank = ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person, name: "Nobank Nel"), amount: 30)
      post manage_add_to_run_money_show_payout_path(show)
      batch = PayoutBatch.where(kind: "performer").order(:id).last
      PayoutBatchService.fund!(batch, method: "ach")
      expect(batch.reload.status).to eq("partially_paid") # Nobank Nel is waiting

      post manage_mark_line_item_paid_money_show_payout_path(show, nobank), params: { payment_method: "cash" }

      nobank.reload
      expect(nobank.manually_paid).to be(true)
      expect(nobank.in_payout_run?).to be(false)
      credit = PayoutFundingCredit.last
      expect(credit.organization).to eq(org)
      expect(credit.amount_cents).to eq(3000)
      # The run has nothing left waiting — it completes.
      expect(batch.reload.status).to eq("completed")

      # The credit shrinks the next run's debit.
      next_batch = PayoutBatch.create!(organization: org, kind: "staff_pay", status: "draft", trigger: "manual")
      next_batch.items.create!(payee: create(:person, name: "Next Ned", stripe_account_id: "acct_n", payouts_enabled: true), amount_cents: 5000, status: "pending")
      next_batch.recalculate_total!
      expect(Stripe::PaymentIntent).to receive(:create).with(hash_including(amount: 2000)).and_return(double("pi", id: "pi_2", status: "succeeded", amount: 2000))
      PayoutBatchService.fund!(next_batch, method: "ach")
      expect(PayoutFundingCredit.available_cents(org)).to eq(0)
    end
  end

  describe "removing a payee from the run" do
    before { post manage_add_to_run_money_show_payout_path(show) } # queues Owed Ollie

    it "offers a Remove from run control while queued" do
      expect(li_unpaid.reload.in_payout_run?).to be(true)
      get manage_money_show_payout_path(show)
      expect(response.body).to include("Remove from run")
    end

    it "pulls the payee out of the open run but keeps them owed" do
      expect(li_unpaid.reload.in_payout_run?).to be(true)

      delete manage_remove_line_item_from_run_money_show_payout_path(show, li_unpaid)

      expect(response).to redirect_to(manage_money_show_payout_path(show))
      expect(li_unpaid.reload.in_payout_run?).to be(false)
      # Still owed — the earning stays on the ledger, only the pending transfer is gone.
      expect(li_unpaid.reload.paid?).to be(false)
    end

    it "never disturbs an already-paid item" do
      # Owed Ollie's transfer completed; removal should be a no-op, not a data wipe.
      contribution = li_unpaid.reload.payout_contribution
      contribution.payout_batch_item.update_columns(status: "paid")

      delete manage_remove_line_item_from_run_money_show_payout_path(show, li_unpaid)

      expect(PayoutContribution.exists?(contribution.id)).to be(true)
    end
  end

  describe "mark paid another way (offline)" do
    # Not bank-connected and unpaid — the only state that offers the offline action.
    let!(:li_offline) do
      ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person, name: "Cash Casey"), amount: 40)
    end

    it "hides the action when the org has declared no offline methods" do
      get manage_money_show_payout_path(show)
      expect(response.body).not_to include("payment-actions#showMarkPaidModal")
    end

    context "with offline methods enabled in Money settings" do
      before { org.update!(enabled_offline_payout_methods: %w[cash zelle]) }

      it "offers the action for a not-bank-connected unpaid payee" do
        get manage_money_show_payout_path(show)
        expect(response.body).to include("payment-actions#showMarkPaidModal")
        expect(response.body).to include('data-item-name="Cash Casey"')
      end

      it "records the offline payment and shows the payee as paid" do
        post manage_mark_line_item_paid_money_show_payout_path(show, li_offline),
          params: { payment_method: "zelle", payment_notes: "Zelle #55" }

        expect(response).to redirect_to(manage_money_show_payout_path(show))
        expect(li_offline.reload).to be_paid
        expect(li_offline.payment_method).to eq("zelle")
        expect(li_offline.payment_notes).to eq("Zelle #55")
        expect(li_offline.payout_reference_id).to be_nil # not a Stripe movement
      end

      it "stamps paid_at from a supplied paid_date" do
        post manage_mark_line_item_paid_money_show_payout_path(show, li_offline),
          params: { payment_method: "cash", paid_date: "2026-05-01" }

        expect(li_offline.reload).to be_paid
        expect(li_offline.paid_at.to_date).to eq(Date.new(2026, 5, 1))
      end
    end
  end

  describe "a line item calculated to nothing owed ($0)" do
    # A custom calculation (or a fully-offset advance) can leave a payee owed nothing.
    let!(:li_zero) do
      ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person, name: "Zero Zoe"), amount: 0)
    end

    it "offers a one-click Mark done instead of the pay-another-way flow" do
      get manage_money_show_payout_path(show)
      expect(response.body).to include("Mark done").and include("nothing owed")
    end

    it "marks the $0 line paid with no method on one click" do
      post manage_mark_line_item_paid_money_show_payout_path(show, li_zero.id.to_s)

      expect(response).to redirect_to(manage_money_show_payout_path(show))
      expect(li_zero.reload).to be_paid
      expect(li_zero.payment_method).to be_nil
    end
  end
end
