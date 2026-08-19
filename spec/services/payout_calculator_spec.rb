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

        it "adds the beyond-the-table rate for each act past the last row when there is one" do
          with_beyond = rules.deep_dup
          with_beyond["distribution"]["additional_act_rate"] = 20.0

          result = described_class.calculate(
            show: show, rules: with_beyond,
            act_counts: { "Person_#{performer1.id}" => 2, "Person_#{performer2.id}" => 4 }
          )

          expect(result[:line_items].find { |li| li.payee == performer1 }.amount.to_f).to eq(50.0)
          expect(result[:line_items].find { |li| li.payee == performer2 }.amount.to_f).to eq(90.0)
          expect(result[:line_items].find { |li| li.payee == performer2 }.calculation_details["breakdown"].first)
            .to eq("1 act $25.00, 2 acts $50.00, then $20.00 per act")
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

      context "with show roles priced by name" do
        let(:production) { create(:production, organization: organization, casting_mode: "act_based") }
        let(:mc_role) { create(:role, production: production, name: "MC", standing: true, position: 0) }
        let(:kitten_role) { create(:role, production: production, name: "Stage Kitten", standing: true, quantity: 2, position: 9) }
        let(:kitten) { create(:person, user: create(:user)) }
        let(:rules) do
          {
            "distribution" => {
              "method" => "per_act",
              "act_mode" => "tiers",
              "tiers" => [ { "acts" => 1, "amount" => 75.0 }, { "acts" => 2, "amount" => 125.0 } ],
              "role_amounts" => [ { "name" => "mc", "amount" => 100.0 } ],
              "role_stacking" => "both"
            }
          }
        end

        before do
          # performer1 is the MC and dances one act; performer2 dances one act;
          # the kitten holds a show role the calculation doesn't price; the guest dances one act.
          create(:show_person_role_assignment, show: show, role: mc_role, assignable: performer1)
          create(:show_person_role_assignment, show: show, role: kitten_role, assignable: kitten)
        end

        def line_for(result, payee)
          result[:line_items].find { |li| li.payee == payee }
        end

        def calculate(rules)
          described_class.calculate(show: show, rules: rules, act_counts: show.lineup_act_counts)
        end

        it "adds the role amount to act pay when they're paid both" do
          result = calculate(rules)
          expect(result[:success]).to be true

          mc = line_for(result, performer1)
          expect(mc.amount.to_f).to eq(175.0)
          expect(mc.calculation_details["formula"]).to eq("MC + 1 act")
          expect(mc.calculation_details["inputs"]).to include("acts" => 1, "roles" => [ "MC" ], "role_pay" => 100.0, "act_pay" => 75.0, "stacking" => "both")
          expect(mc.calculation_details["breakdown"]).to include("Show roles: MC $100.00", "1 act = $75.00")

          plain = line_for(result, performer2)
          expect(plain.amount.to_f).to eq(75.0)
          expect(plain.calculation_details["formula"]).to eq("1 act")
          expect(plain.calculation_details["inputs"]).to eq("acts" => 1)
        end

        it "pays the role amount alone when the person performs no acts" do
          host = create(:person, user: create(:user))
          create(:show_person_role_assignment, show: show, role: create(:role, production: production, name: "Host", standing: true), assignable: host)
          with_host = rules.deep_dup
          with_host["distribution"]["role_amounts"] << { "name" => "Host", "amount" => 60.0 }

          line = line_for(calculate(with_host), host)
          expect(line.amount.to_f).to eq(60.0)
          expect(line.calculation_details["formula"]).to eq("Host")
        end

        it "pays the role only when that's the stacking" do
          role_only = rules.deep_dup
          role_only["distribution"]["role_stacking"] = "role_only"

          mc = line_for(calculate(role_only), performer1)
          expect(mc.amount.to_f).to eq(100.0)
          expect(mc.calculation_details["formula"]).to eq("MC (role only; 1 act not paid on top)")
        end

        it "pays whichever is higher when that's the stacking" do
          higher = rules.deep_dup
          higher["distribution"]["role_stacking"] = "higher"

          mc = line_for(calculate(higher), performer1)
          expect(mc.amount.to_f).to eq(100.0)
          expect(mc.calculation_details["formula"]).to eq("MC (higher than 1 act)")

          cheap_role = higher.deep_dup
          cheap_role["distribution"]["role_amounts"] = [ { "name" => "MC", "amount" => 20.0 } ]
          mc = line_for(calculate(cheap_role), performer1)
          expect(mc.amount.to_f).to eq(75.0)
          expect(mc.calculation_details["formula"]).to eq("1 act (higher than MC)")
        end

        it "pays one set amount, all in, for a role holder who also performs" do
          flat = rules.deep_dup
          flat["distribution"].merge!("role_stacking" => "flat", "role_with_acts_amount" => 150.0)

          mc = line_for(calculate(flat), performer1)
          expect(mc.amount.to_f).to eq(150.0)
          expect(mc.calculation_details["formula"]).to eq("MC with 1 act (set amount)")
          expect(mc.calculation_details["breakdown"].last).to eq("Show role holder with 1 act, all in: $150.00")
          # Everyone without the role is unaffected
          expect(line_for(calculate(flat), performer2).amount.to_f).to eq(75.0)
        end

        it "reads a role holder's own act table, all in, by how many acts they did" do
          table = rules.deep_dup
          table["distribution"].merge!(
            "role_stacking" => "table",
            "role_with_acts_tiers" => [ { "acts" => 1, "amount" => 120.0 }, { "acts" => 2, "amount" => 160.0 } ],
            "role_with_acts_additional_rate" => 30.0
          )

          mc = line_for(calculate(table), performer1)
          expect(mc.amount.to_f).to eq(120.0)
          expect(mc.calculation_details["formula"]).to eq("MC with 1 act (role-holder table)")

          # Past the last row each further act adds the beyond rate
          counts = show.lineup_act_counts.merge(ShowPayout.act_key(performer1) => 4)
          result = described_class.calculate(show: show, rules: table, act_counts: counts)
          expect(line_for(result, performer1).amount.to_f).to eq(220.0)
        end

        it "still pays the role amount alone under flat or table when they did no acts" do
          flat = rules.deep_dup
          flat["distribution"].merge!("role_stacking" => "flat", "role_with_acts_amount" => 150.0)
          counts = show.lineup_act_counts.merge(ShowPayout.act_key(performer1) => 0)
          result = described_class.calculate(show: show, rules: flat, act_counts: counts)
          expect(line_for(result, performer1).amount.to_f).to eq(100.0)
        end

        it "pays act pay alone for a show role the calculation doesn't price, and says so" do
          line = line_for(calculate(rules), kitten)
          expect(line.amount.to_f).to eq(0.0)
          expect(line.calculation_details["formula"]).to eq("0 acts")
          expect(line.calculation_details["inputs"]).to eq("acts" => 0, "roles" => [ "Stage Kitten" ])
          expect(line.calculation_details["breakdown"]).to include("Stage Kitten: not priced in this calculation")
        end

        it "prices a guest's show role too" do
          create(:show_person_role_assignment, show: show, role: mc_role, guest_name: "Guest Star", assignable: nil)
          # The guest already dances one act (see the outer before); the MC slot is a second assignment.
          result = calculate(rules)
          guest_line = result[:line_items].find(&:is_guest?)
          expect(guest_line.amount.to_f).to eq(175.0)
          expect(guest_line.calculation_details["formula"]).to eq("MC + 1 act")
        end

        it "still lets a set amount for this show win" do
          custom = rules.deep_dup
          custom["performer_overrides"] = { "Person_#{performer1.id}" => { "flat_amount" => 12.0 } }
          mc = line_for(calculate(custom), performer1)
          expect(mc.amount.to_f).to eq(12.0)
          expect(mc.calculation_details["inputs"]).to include("roles" => [ "MC" ], "custom" => true)
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

    context "with shares and a guest" do
      let!(:guest) { create(:show_person_role_assignment, show: show, role: role, guest_name: "Guest Star", assignable: nil) }

      before do
        create(:show_financials, :complete, show: show, ticket_revenue: 300.0, expenses: 0.0)
        create(:show_payout, show: show)
      end

      it "counts the guest as default_shares worth and keeps everyone's shares intact" do
        rules = {
          "distribution" => { "method" => "shares", "default_shares" => 1.0 },
          "performer_overrides" => { "Person_#{performer1.id}" => { "shares" => 2.0 } }
        }

        result = described_class.calculate(show: show, rules: rules)
        expect(result[:success]).to be(true), result[:error]

        items = result[:line_items]
        two_shares = items.find { |li| li.payee == performer1 }
        one_share = items.find { |li| li.payee == performer2 }
        guest_line = items.find(&:is_guest?)

        # $300 over 4 shares (2 + 1 + guest 1) = $75/share
        expect(two_shares.amount.to_f).to eq(150.0)
        expect(two_shares.shares.to_f).to eq(2.0)
        expect(two_shares.calculation_details["formula"]).to eq("$300.00 × (2.0 ÷ 4.0 shares)")
        expect(one_share.amount.to_f).to eq(75.0)
        expect(one_share.shares.to_f).to eq(1.0)
        expect(guest_line.amount.to_f).to eq(75.0)
        expect(guest_line.shares.to_f).to eq(1.0)
        expect(guest_line.calculation_details["guest_assignment_id"]).to eq(guest.id)
        expect(result[:total]).to eq(300.0)
      end
    end

    context "as a dry run (persist: false)" do
      before do
        create(:show_financials, :complete, show: show, ticket_revenue: 1000.0, expenses: 200.0)
        create(:show_payout, show: show)
      end

      it "returns the same numbers as hashes and writes nothing" do
        result = described_class.calculate(show: show, rules: { "distribution" => { "method" => "equal" } }, persist: false)

        expect(result[:success]).to be(true)
        expect(result[:total]).to eq(800.0)
        expect(result[:line_items]).to all(be_a(Hash))
        expect(result[:line_items].map { |li| li[:amount] }).to eq([ 400.0, 400.0 ])
        expect(result[:line_items].map { |li| li[:payee] }).to contain_exactly(performer1, performer2)

        payout = show.reload.show_payout
        expect(payout.line_items).to be_empty
        expect(payout.calculated_at).to be_nil
        expect(PayoutLedgerEntry.where(payee: performer1)).to be_empty
      end
    end

    context "with a person and a group sharing an id" do
      let(:shared_id) { [ Person.maximum(:id).to_i, Group.maximum(:id).to_i ].max + 1 }
      let!(:person) { create(:person, id: shared_id) }
      let!(:group) { create(:group, id: shared_id) }

      before do
        show.show_person_role_assignments.destroy_all
        create(:show_person_role_assignment, show: show, role: role, assignable: person)
        create(:show_person_role_assignment, show: show, role: role, assignable: group)
        create(:show_financials, :complete, show: show, ticket_revenue: 1000.0, expenses: 0.0)
        create(:show_payout, show: show)
      end

      it "pays each their own customized amount" do
        rules = {
          "distribution" => { "method" => "flat_fee", "flat_amount" => 50.0 },
          "performer_overrides" => { "Person_#{shared_id}" => { "flat_amount" => 10.0 }, "Group_#{shared_id}" => { "flat_amount" => 90.0 } }
        }
        result = described_class.calculate(show: show, rules: rules)
        expect(result[:success]).to be(true), result[:error]

        expect(result[:line_items].find { |li| li.payee == person }.amount.to_f).to eq(10.0)
        expect(result[:line_items].find { |li| li.payee == group }.amount.to_f).to eq(90.0)
      end

      it "reads an older bare-id key as the person, never the group" do
        rules = {
          "distribution" => { "method" => "flat_fee", "flat_amount" => 50.0 },
          "performer_overrides" => { shared_id.to_s => { "flat_amount" => 10.0 } }
        }
        result = described_class.calculate(show: show, rules: rules)

        expect(result[:line_items].find { |li| li.payee == person }.amount.to_f).to eq(10.0)
        expect(result[:line_items].find { |li| li.payee == group }.amount.to_f).to eq(50.0)
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

  # An exact amount set for one person tonight (performer_overrides[act_key]
  # ["flat_amount"]) wins under every method — for cast and for guests.
  describe "an exact per-person amount" do
    let!(:guest) { create(:show_person_role_assignment, show: show, role: role, guest_name: "Gigi", assignable: nil) }
    let(:overrides) { { "Person_#{performer1.id}" => { "flat_amount" => 99.0 }, "guest_#{guest.id}" => { "flat_amount" => 11.0 } } }

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
