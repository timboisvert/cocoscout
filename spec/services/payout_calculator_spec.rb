# frozen_string_literal: true

require "rails_helper"

RSpec.describe PayoutCalculator do
  let(:organization) { create(:organization) }
  let(:production) { create(:production, organization: organization) }
  let(:show) { create(:show, production: production, date_and_time: 1.day.ago) }
  let(:role) { create(:role, production: production) }

  # Create performers
  let(:performer1) { create(:person, user: create(:user)) }
  let(:performer2) { create(:person, user: create(:user)) }

  before do
    # Assign performers to show
    create(:show_person_role_assignment, show: show, role: role, assignable: performer1)
    create(:show_person_role_assignment, show: show, role: role, assignable: performer2)
  end

  describe ".calculate" do
    context "with equal distribution" do
      let(:rules) do
        {
          "distribution" => {
            "method" => "equal"
          }
        }
      end

      before do
        create(:show_financials, :complete,
               show: show,
               ticket_count: 100,
               ticket_revenue: 1000.0,
               expenses: 200.0)
        create(:show_payout, show: show)
      end

      it "calculates equal payouts for all performers" do
        result = described_class.calculate(show: show, rules: rules)

        expect(result[:success]).to be true
        expect(result[:line_items].size).to eq(2)

        # Net revenue = 1000 - 200 = 800, split 2 ways = 400 each
        expect(result[:line_items].first[:amount]).to eq(400.0)
        expect(result[:line_items].last[:amount]).to eq(400.0)
        expect(result[:total]).to eq(800.0)
      end

      it "creates payout records" do
        result = described_class.calculate(show: show, rules: rules)

        show_payout = show.reload.show_payout
        expect(show_payout).to be_present
        expect(show_payout.line_items.count).to eq(2)
      end
    end

    context "with per_ticket distribution" do
      let(:rules) do
        {
          "distribution" => {
            "method" => "per_ticket",
            "per_ticket_rate" => 2.0
          }
        }
      end

      before do
        create(:show_financials, :complete,
               show: show,
               ticket_count: 100,
               ticket_revenue: 1000.0,
               expenses: 200.0)
        create(:show_payout, show: show)
      end

      it "calculates based on ticket count" do
        result = described_class.calculate(show: show, rules: rules)

        expect(result[:success]).to be true
        # 100 tickets * $2/ticket = $200 per performer
        expect(result[:line_items].first[:amount]).to eq(200.0)
      end
    end

    context "with per_ticket_guaranteed distribution" do
      let(:rules) do
        {
          "distribution" => {
            "method" => "per_ticket_guaranteed",
            "per_ticket_rate" => 2.0,
            "minimum" => 150.0
          }
        }
      end

      before do
        create(:show_financials, :complete,
               show: show,
               ticket_count: 50,  # Only 50 tickets
               ticket_revenue: 500.0,
               expenses: 100.0)
        create(:show_payout, show: show)
      end

      it "uses guaranteed minimum when per_ticket is lower" do
        result = described_class.calculate(show: show, rules: rules)

        expect(result[:success]).to be true
        # 50 tickets * $2 = $100 per person, but minimum is $150
        expect(result[:line_items].first[:amount]).to eq(150.0)
      end

      it "pays a guest by the same per-ticket rule instead of re-splitting the pool" do
        guest = create(:show_person_role_assignment, show: show, role: role, guest_name: "Gigi", assignable: nil)

        result = described_class.calculate(show: show, rules: rules)

        expect(result[:success]).to be true
        amounts = show.show_payout.line_items.reload.map { |li| [ li.is_guest?, li.amount.to_f ] }
        expect(amounts).to all(satisfy { |(_, amount)| amount == 150.0 })
        expect(show.show_payout.line_items.find_by(is_guest: true, guest_name: "Gigi").calculation_details["formula"]).to include("Minimum")
        expect(guest).to be_persisted
      end
    end

    context "with flat_fee distribution" do
      let(:rules) do
        {
          "distribution" => {
            "method" => "flat_fee",
            "flat_amount" => 75.0
          }
        }
      end

      before do
        create(:show_financials, :complete,
               show: show,
               ticket_revenue: 1000.0,
               expenses: 0.0)
        create(:show_payout, show: show)
      end

      it "pays each performer the flat amount" do
        result = described_class.calculate(show: show, rules: rules)

        expect(result[:success]).to be true
        expect(result[:line_items].first[:amount]).to eq(75.0)
        expect(result[:line_items].last[:amount]).to eq(75.0)
        expect(result[:total]).to eq(150.0)
      end
    end

    context "with no_pay distribution" do
      let(:rules) do
        {
          "distribution" => {
            "method" => "no_pay"
          }
        }
      end

      before do
        create(:show_financials, :complete, show: show, ticket_revenue: 1000.0)
        create(:show_payout, show: show)
      end

      it "sets all payouts to zero" do
        result = described_class.calculate(show: show, rules: rules)

        expect(result[:success]).to be true
        expect(result[:line_items].all? { |li| li[:amount] == 0.0 }).to be true
      end
    end

    context "with performer overrides" do
      let(:rules) do
        {
          "distribution" => {
            "method" => "equal"
          },
          "performer_overrides" => {
            performer1.id.to_s => {
              "flat_amount" => 500.0
            }
          }
        }
      end

      before do
        create(:show_financials, :complete,
               show: show,
               ticket_revenue: 1000.0,
               expenses: 200.0)
        create(:show_payout, show: show)
      end

      it "applies override for specific performer" do
        result = described_class.calculate(show: show, rules: rules)

        expect(result[:success]).to be true

        performer1_item = result[:line_items].find { |li| li.payee == performer1 }
        # The override for fixed type=500 should be applied
        expect(performer1_item.amount.to_f).to eq(500.0)
      end
    end

    context "with per_act distribution" do
      let(:guest_assignment) do
        create(:show_person_role_assignment, show: show, role: role, guest_name: "Guest Star", assignable: nil)
      end

      before do
        guest_assignment
        create(:show_financials, :complete, show: show, ticket_revenue: 1000.0, expenses: 0.0)
        create(:show_payout, show: show)
      end

      context "with a table of act counts" do
        let(:rules) do
          {
            "distribution" => {
              "method" => "per_act",
              "act_mode" => "tiers",
              "tiers" => [ { "acts" => 1, "amount" => 25.0 }, { "acts" => 2, "amount" => 50.0 } ]
            }
          }
        end

        it "pays each person the tier their act count reaches" do
          result = described_class.calculate(
            show: show,
            rules: rules,
            act_counts: {
              "Person_#{performer1.id}" => 1,
              "Person_#{performer2.id}" => 2,
              "guest_#{guest_assignment.id}" => 2
            }
          )

          expect(result[:success]).to be true
          expect(result[:line_items].find { |li| li.payee == performer1 }.amount.to_f).to eq(25.0)
          expect(result[:line_items].find { |li| li.payee == performer2 }.amount.to_f).to eq(50.0)
          expect(result[:line_items].find(&:is_guest?).amount.to_f).to eq(50.0)
          expect(result[:total]).to eq(125.0)
        end

        it "pays the top tier to anyone who does more acts than the table covers" do
          result = described_class.calculate(
            show: show, rules: rules, act_counts: { "Person_#{performer1.id}" => 5 }
          )

          expect(result[:line_items].find { |li| li.payee == performer1 }.amount.to_f).to eq(50.0)
        end

        it "pays nothing to someone with no acts" do
          result = described_class.calculate(show: show, rules: rules, act_counts: {})

          expect(result[:success]).to be true
          expect(result[:total]).to eq(0.0)
          expect(result[:line_items].map { |li| li.amount.to_f }).to all(eq(0.0))
        end

        it "records the act count on the line item" do
          result = described_class.calculate(
            show: show, rules: rules, act_counts: { "Person_#{performer1.id}" => 2 }
          )

          item = result[:line_items].find { |li| li.payee == performer1 }
          expect(item.calculation_details["inputs"]["acts"]).to eq(2)
          expect(item.calculation_explanation).to eq("2 acts")
        end

        it "ignores ticket revenue entirely" do
          show.show_financials.update!(ticket_revenue: 99_999.0)

          result = described_class.calculate(
            show: show, rules: rules, act_counts: { "Person_#{performer1.id}" => 1 }
          )

          expect(result[:total]).to eq(25.0)
        end
      end

      context "before any financials are entered" do
        let(:rules) do
          {
            "distribution" => { "method" => "per_act", "act_mode" => "simple", "per_act_rate" => 20.0 }
          }
        end

        it "still calculates — act pay never reads revenue" do
          show.show_financials.destroy!
          show.reload

          result = described_class.calculate(
            show: show, rules: rules, act_counts: { "Person_#{performer1.id}" => 2, "Person_#{performer2.id}" => 1 }
          )

          expect(result[:success]).to be true
          expect(result[:total]).to eq(60.0)
        end

        it "calculates when the financials are only partly filled in" do
          show.show_financials.update_columns(data_confirmed: false, ticket_revenue: nil)
          expect(show.reload.show_financials).not_to be_complete

          result = described_class.calculate(
            show: show, rules: rules, act_counts: { "Person_#{performer1.id}" => 1 }
          )

          expect(result[:success]).to be true
          expect(result[:total]).to eq(20.0)
        end
      end

      context "in an act-based production" do
        let(:production) { create(:production, organization: organization, casting_mode: "act_based") }
        let(:second_role) { create(:role, production: production, name: "Second Half Magic") }
        let(:rules) do
          {
            "distribution" => { "method" => "per_act", "act_mode" => "simple", "per_act_rate" => 20.0 }
          }
        end

        before do
          # Guest Star holds a second act too — one payee, two acts.
          create(:show_person_role_assignment, show: show, role: second_role, guest_name: "Guest Star", assignable: nil)
        end

        it "pays a guest in two acts once, for two acts, straight from the lineup" do
          counts = show.lineup_act_counts
          expect(counts["guest_#{guest_assignment.id}"]).to eq(2)

          result = described_class.calculate(show: show, rules: rules, act_counts: counts)

          expect(result[:success]).to be true
          guest_items = result[:line_items].select(&:is_guest?)
          expect(guest_items.size).to eq(1)
          expect(guest_items.first.guest_name).to eq("Guest Star")
          expect(guest_items.first.calculation_details["inputs"]["acts"]).to eq(2)
          expect(guest_items.first.amount.to_f).to eq(40.0)
        end
      end

      context "with a rate for each act that adds up" do
        let(:rules) do
          {
            "distribution" => {
              "method" => "per_act",
              "act_mode" => "schedule",
              "act_rates" => [ { "act" => 1, "amount" => 75.0 }, { "act" => 2, "amount" => 50.0 } ],
              "additional_act_rate" => 25.0
            }
          }
        end

        it "adds each act's own rate together" do
          result = described_class.calculate(
            show: show,
            rules: rules,
            act_counts: { "Person_#{performer1.id}" => 1, "Person_#{performer2.id}" => 2 }
          )

          expect(result[:line_items].find { |li| li.payee == performer1 }.amount.to_f).to eq(75.0)
          expect(result[:line_items].find { |li| li.payee == performer2 }.amount.to_f).to eq(125.0)
        end

        it "pays the additional rate for acts past the end of the list" do
          result = described_class.calculate(
            show: show, rules: rules, act_counts: { "Person_#{performer1.id}" => 4 }
          )

          # 75 + 50 + 25 + 25
          expect(result[:line_items].find { |li| li.payee == performer1 }.amount.to_f).to eq(175.0)
        end

        it "stops paying past the list when there is no additional rate" do
          capped = rules.deep_dup
          capped["distribution"].delete("additional_act_rate")

          result = described_class.calculate(
            show: show, rules: capped, act_counts: { "Person_#{performer1.id}" => 5 }
          )

          expect(result[:line_items].find { |li| li.payee == performer1 }.amount.to_f).to eq(125.0)
        end

        it "spells the schedule out on the line item" do
          result = described_class.calculate(
            show: show, rules: rules, act_counts: { "Person_#{performer1.id}" => 2 }
          )

          item = result[:line_items].find { |li| li.payee == performer1 }
          expect(item.calculation_details["breakdown"].first)
            .to eq("1st act $75.00, 2nd act $50.00, then $25.00 each")
        end
      end

      context "with a flat rate per act" do
        let(:rules) do
          {
            "distribution" => { "method" => "per_act", "act_mode" => "simple", "per_act_rate" => 20.0 }
          }
        end

        it "multiplies the rate by the act count" do
          result = described_class.calculate(
            show: show, rules: rules, act_counts: { "Person_#{performer1.id}" => 3 }
          )

          expect(result[:line_items].find { |li| li.payee == performer1 }.amount.to_f).to eq(60.0)
        end

        it "honours a per-performer rate override" do
          rules_with_override = rules.merge(
            "performer_overrides" => { performer1.id.to_s => { "per_act_rate" => 40.0 } }
          )

          result = described_class.calculate(
            show: show, rules: rules_with_override,
            act_counts: { "Person_#{performer1.id}" => 2, "Person_#{performer2.id}" => 2 }
          )

          expect(result[:line_items].find { |li| li.payee == performer1 }.amount.to_f).to eq(80.0)
          expect(result[:line_items].find { |li| li.payee == performer2 }.amount.to_f).to eq(40.0)
        end
      end
    end

    context "with guest performers" do
      before do
        # Add a guest assignment
        create(:show_person_role_assignment,
               show: show,
               role: role,
               guest_name: "Guest Star",
               assignable: nil)

        create(:show_financials, :complete,
               show: show,
               ticket_revenue: 1200.0,
               expenses: 0.0)
        create(:show_payout, show: show)
      end

      let(:rules) do
        {
          "distribution" => {
            "method" => "equal"
          }
        }
      end

      it "includes guest in payout calculation" do
        result = described_class.calculate(show: show, rules: rules)

        expect(result[:success]).to be true
        # 3 performers total (2 regular + 1 guest)
        expect(result[:line_items].size).to eq(3)
        guest_items = result[:line_items].select(&:is_guest?)
        regular_items = result[:line_items].reject(&:is_guest?)
        expect(guest_items.size).to eq(1)
        expect(regular_items.size).to eq(2)
        expect(guest_items.first.guest_name).to eq("Guest Star")
      end
    end

    context "error cases" do
      it "returns error when no show provided" do
        result = described_class.calculate(show: nil, rules: {})
        expect(result[:success]).to be false
        expect(result[:error]).to eq("No show provided")
      end

      it "returns error when no rules provided" do
        result = described_class.calculate(show: show, rules: nil)
        expect(result[:success]).to be false
        expect(result[:error]).to eq("No rules provided")
      end

      it "returns error when no financials" do
        result = described_class.calculate(show: show, rules: { "distribution" => {} })
        expect(result[:success]).to be false
        expect(result[:error]).to eq("No financial data")
      end

      it "returns error when financials incomplete" do
        create(:show_financials, show: show, data_confirmed: false, ticket_revenue: nil, flat_fee: nil)
        result = described_class.calculate(show: show, rules: { "distribution" => {} })
        expect(result[:success]).to be false
        expect(result[:error]).to eq("No financial data")
      end

      it "returns error when no performers" do
        show.show_person_role_assignments.destroy_all
        create(:show_financials, :complete, show: show)

        result = described_class.calculate(show: show, rules: { "distribution" => {} })
        expect(result[:success]).to be false
        expect(result[:error]).to eq("No performers assigned to this show")
      end
    end
  end

  describe ".preview" do
    it "calculates preview without persisting" do
      result = described_class.preview(
        rules: { "distribution" => { "method" => "equal" } },
        financials: { ticket_count: 100, ticket_revenue: 1000, expenses: 200, net_revenue: 800 },
        performer_count: 4
      )

      expect(result[:success]).to be true
      expect(result[:per_person]).to eq(200.0)  # 800 / 4
      expect(ShowPayout.count).to eq(0)  # Nothing persisted
    end

    it "returns preview for flat_fee method" do
      result = described_class.preview(
        rules: { "distribution" => { "method" => "flat_fee", "flat_amount" => 50.0 } },
        financials: { ticket_revenue: 1000 },
        performer_count: 3
      )

      expect(result[:success]).to be true
      expect(result[:per_person]).to eq(50.0)
      expect(result[:total]).to eq(150.0)
    end
  end

  # Schemes used to be able to exclude a role from payouts ("excluded_role_ids").
  # It was configured once in production and never actually kept anyone out, so
  # it was removed — every assigned role is paid.
  describe "everyone assigned to the show" do
    let(:tech_role) { create(:role, production: production, name: "Tech", category: "technical") }
    let(:performer_role) { create(:role, production: production, name: "Performer", category: "performing") }
    let(:tech_person) { create(:person, user: create(:user)) }

    before do
      show.show_person_role_assignments.destroy_all
      create(:show_person_role_assignment, show: show, role: performer_role, assignable: performer1)
      create(:show_person_role_assignment, show: show, role: performer_role, assignable: performer2)
      create(:show_person_role_assignment, show: show, role: tech_role, assignable: tech_person)

      create(:show_financials, :complete, show: show, ticket_count: 100, ticket_revenue: 1000.0, expenses: 0.0)
      create(:show_payout, show: show)
    end

    it "pays everyone on the show, whatever role they hold" do
      result = described_class.calculate(show: show, rules: { "distribution" => { "method" => "equal" } })

      expect(result[:success]).to be true
      expect(result[:line_items].map(&:payee_id)).to include(performer1.id, performer2.id, tech_person.id)
      expect(result[:line_items].map { |li| li.amount.to_f }).to all(eq(333.33))
    end

    it "pays a technical role the flat fee too" do
      result = described_class.calculate(
        show: show, rules: { "distribution" => { "method" => "flat_fee", "flat_amount" => 75.0 } }
      )

      expect(result[:line_items].size).to eq(3)
      expect(result[:total]).to eq(225.0)
    end

    it "ignores a stale excluded_role_ids key left behind in stored rules" do
      result = described_class.calculate(show: show, rules: {
        "distribution" => { "method" => "equal" },
        "excluded_role_ids" => [ tech_role.id ]
      })

      expect(result[:line_items].map(&:payee_id)).to include(tech_person.id)
      expect(result[:line_items].size).to eq(3)
    end
  end

  # An exact amount set for one person tonight (performer_overrides["<id>"]
  # ["flat_amount"]) wins under every method — for cast and for guests.
  describe "an exact per-person amount" do
    let!(:guest) { create(:show_person_role_assignment, show: show, role: role, guest_name: "Gigi", assignable: nil) }
    let(:overrides) { { performer1.id.to_s => { "flat_amount" => 99.0 }, "guest_#{guest.id}" => { "flat_amount" => 11.0 } } }

    before do
      create(:show_financials, :complete, show: show, ticket_count: 100, ticket_revenue: 900.0, expenses: 0.0)
      create(:show_payout, show: show)
    end

    # act_counts may key performer2 as "Person_PERF2" — ids aren't known when
    # the shared examples below are declared.
    def amounts_for(distribution, act_counts: {})
      act_counts = act_counts.transform_keys { |k| k.sub("PERF2", performer2.id.to_s) }
      result = described_class.calculate(show: show, rules: { "distribution" => distribution, "performer_overrides" => overrides }, act_counts: act_counts)
      expect(result[:success]).to be(true), result[:error]
      items = show.show_payout.line_items.reload
      {
        custom: items.find_by(payee: performer1),
        other: items.find_by(payee: performer2),
        guest: items.find_by(is_guest: true)
      }
    end

    shared_examples "honours the exact amounts" do |distribution, other_amount, act_counts: {}|
      it "under #{distribution['method']}" do
        items = amounts_for(distribution, act_counts: act_counts)
        expect(items[:custom].amount.to_f).to eq(99.0)
        expect(items[:custom].calculation_details["formula"]).to eq("Custom amount")
        expect(items[:guest].amount.to_f).to eq(11.0)
        expect(items[:guest].calculation_details["formula"]).to eq("Custom amount")
        expect(items[:other].amount.to_f).to eq(other_amount)
        expect(items[:other].calculation_details["formula"]).not_to eq("Custom amount")
      end
    end

    include_examples "honours the exact amounts", { "method" => "equal" }, 300.0
    include_examples "honours the exact amounts", { "method" => "shares", "default_shares" => 1.0 }, 300.0
    include_examples "honours the exact amounts", { "method" => "per_ticket", "per_ticket_rate" => 2.0 }, 200.0
    include_examples "honours the exact amounts", { "method" => "per_ticket_guaranteed", "per_ticket_rate" => 1.0, "minimum" => 150.0 }, 150.0
    include_examples "honours the exact amounts", { "method" => "flat_fee", "flat_amount" => 50.0 }, 50.0
    include_examples "honours the exact amounts", { "method" => "no_pay" }, 0.0
    include_examples "honours the exact amounts", { "method" => "per_act", "act_mode" => "simple", "per_act_rate" => 20.0 }, 40.0,
                     act_counts: { "Person_PERF2" => 2 }
  end
end
