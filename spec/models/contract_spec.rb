# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contract, type: :model do
  describe "associations" do
    let(:contract) { create(:contract) }

    it "belongs to organization" do
      expect(contract).to respond_to(:organization)
      expect(contract.organization).to be_present
    end

    it "has many contract_documents" do
      expect(contract).to respond_to(:contract_documents)
    end

    it "has many contract_payments" do
      expect(contract).to respond_to(:contract_payments)
    end

    it "has many space_rentals" do
      expect(contract).to respond_to(:space_rentals)
    end

    it "belongs to a production" do
      expect(contract).to respond_to(:production)
    end
  end

  describe "validations" do
    it "requires contractor_name" do
      contract = build(:contract, contractor_name: nil)
      expect(contract).not_to be_valid
      expect(contract.errors[:contractor_name]).to be_present
    end

    it "allows nil contractor_email" do
      contract = build(:contract, contractor_email: nil)
      expect(contract).to be_valid
    end
  end

  describe "enums" do
    it "defines status enum" do
      expect(described_class.statuses).to include(
        "draft" => "draft",
        "active" => "active",
        "completed" => "completed",
        "cancelled" => "cancelled"
      )
    end
  end

  describe "scopes" do
    let(:organization) { create(:organization) }
    let!(:draft_contract) { create(:contract, organization: organization, status: :draft) }
    let!(:active_contract) { create(:contract, :active, organization: organization) }
    let!(:completed_contract) { create(:contract, :completed, organization: organization) }
    let!(:cancelled_contract) { create(:contract, :cancelled, organization: organization) }

    describe ".status_active" do
      it "returns only active contracts" do
        expect(described_class.status_active).to contain_exactly(active_contract)
      end
    end

    describe ".status_draft" do
      it "returns only draft contracts" do
        expect(described_class.status_draft).to contain_exactly(draft_contract)
      end
    end

    describe ".status_completed" do
      it "returns only completed contracts" do
        expect(described_class.status_completed).to contain_exactly(completed_contract)
      end
    end

    describe ".status_cancelled" do
      it "returns only cancelled contracts" do
        expect(described_class.status_cancelled).to contain_exactly(cancelled_contract)
      end
    end
  end

  describe "lifecycle methods" do
    describe "#activate!" do
      let(:organization) { create(:organization) }
      let(:location) { create(:location, organization: organization) }
      let(:contract) do
        create(:contract, organization: organization,
          contract_start_date: Date.current,
          contract_end_date: Date.current + 7.days,
          draft_data: {
            "bookings" => [
              {
                "location_id" => location.id,
                "starts_at" => 1.day.from_now.iso8601,
                "ends_at" => (1.day.from_now + 3.hours).iso8601
              }
            ],
            "payments" => [
              {
                "description" => "Rental fee",
                "amount" => 1000,
                "direction" => "incoming",
                "due_date" => Date.current + 7.days
              }
            ]
          })
      end

      context "when contract is valid for activation" do
        it "changes status to active" do
          contract.activate!
          expect(contract.reload.status).to eq("active")
        end

        it "creates space rentals from draft bookings" do
          expect { contract.activate! }.to change { contract.space_rentals.count }.by(1)
        end

        it "creates contract payments from draft payments" do
          expect { contract.activate! }.to change { contract.contract_payments.count }.by(1)
        end

        it "creates a production for the contract" do
          expect { contract.activate! }.to change { contract.reload.production }.from(nil)
        end

        it "creates shows for each space rental" do
          contract.activate!
          production = contract.reload.production
          expect(production.shows.count).to eq(1)
        end
      end

      context "when contract is not valid for activation" do
        let(:invalid_contract) { create(:contract, organization: organization) }

        it "returns false" do
          expect(invalid_contract.activate!).to be false
        end

        it "does not change status" do
          invalid_contract.activate!
          expect(invalid_contract.reload.status).to eq("draft")
        end
      end
    end

    describe "#complete!" do
      let(:contract) { create(:contract, :active) }

      it "changes status to completed" do
        contract.complete!
        expect(contract.reload.status).to eq("completed")
      end

      it "sets completed_at timestamp" do
        contract.complete!
        expect(contract.completed_at).to be_present
      end
    end

    describe "#reopen!" do
      it "flips a completed contract back to active and clears completed_at" do
        contract = create(:contract, :completed)
        expect(contract.reopen!).to be(true)
        expect(contract.reload.status).to eq("active")
        expect(contract.completed_at).to be_nil
      end

      it "un-archives the production that was archived on completion" do
        production = create(:production, organization: create(:organization), archived_at: Time.current)
        contract = create(:contract, :completed, organization: production.organization, production: production)
        contract.reopen!
        expect(production.reload.archived_at).to be_nil
      end

      it "does nothing for a contract that isn't completed" do
        contract = create(:contract, :active)
        expect(contract.reopen!).to be(false)
        expect(contract.reload.status).to eq("active")
      end
    end

    describe "#cancel!" do
      let(:contract) { create(:contract, :active) }

      it "changes status to cancelled" do
        contract.cancel!
        expect(contract.reload.status).to eq("cancelled")
      end
    end
  end

  describe "#valid_for_activation?" do
    let(:organization) { create(:organization) }
    let(:location) { create(:location, organization: organization) }

    context "when contract has bookings and dates" do
      let(:contract) do
        create(:contract, organization: organization,
          contract_start_date: Date.current,
          contract_end_date: Date.current + 7.days,
          draft_data: {
            "bookings" => [
              { "location_id" => location.id, "starts_at" => 1.day.from_now.iso8601, "ends_at" => (1.day.from_now + 2.hours).iso8601 }
            ]
          })
      end

      it "returns true" do
        expect(contract.valid_for_activation?).to be true
      end
    end

    context "when contract has no bookings and no space rentals" do
      let(:contract) do
        create(:contract, organization: organization,
          contract_start_date: Date.current,
          contract_end_date: Date.current + 7.days)
      end

      it "returns false" do
        expect(contract.valid_for_activation?).to be false
      end

      it "adds error about bookings" do
        contract.valid_for_activation?
        expect(contract.errors[:base]).to include("Must have at least one booking")
      end
    end

    context "when contract has no start date" do
      let(:contract) do
        create(:contract, organization: organization,
          contract_start_date: nil,
          contract_end_date: Date.current + 7.days,
          draft_data: { "bookings" => [ { "location_id" => location.id, "starts_at" => 1.day.from_now.iso8601, "ends_at" => (1.day.from_now + 2.hours).iso8601 } ] })
      end

      it "returns false" do
        expect(contract.valid_for_activation?).to be false
      end

      it "adds error about start date" do
        contract.valid_for_activation?
        expect(contract.errors[:base]).to include("Contract start date is required")
      end
    end

    context "when contract has no end date" do
      let(:contract) do
        create(:contract, organization: organization,
          contract_start_date: Date.current,
          contract_end_date: nil,
          draft_data: { "bookings" => [ { "location_id" => location.id, "starts_at" => 1.day.from_now.iso8601, "ends_at" => (1.day.from_now + 2.hours).iso8601 } ] })
      end

      it "returns false" do
        expect(contract.valid_for_activation?).to be false
      end

      it "adds error about end date" do
        contract.valid_for_activation?
        expect(contract.errors[:base]).to include("Contract end date is required")
      end
    end
  end

  describe "draft data helpers" do
    let(:contract) do
      create(:contract, draft_data: {
        "bookings" => [ { "location_id" => 1 } ],
        "booking_rules" => { "min_duration" => 2 },
        "payments" => [ { "amount" => 500 } ],
        "payment_structure" => "per_hour",
        "payment_config" => { "hourly_rate" => 50 },
        "ticketing" => { "tiers" => [ { "name" => "General", "price" => 25.0 } ] },
        "tech" => { "provider" => "us", "hourly_rate" => 25.0, "hours" => 2.0 }
      })
    end

    describe "#draft_bookings" do
      it "returns bookings from draft_data" do
        expect(contract.draft_bookings).to eq([ { "location_id" => 1 } ])
      end

      it "returns empty array when not set" do
        contract.update!(draft_data: {})
        expect(contract.draft_bookings).to eq([])
      end
    end

    describe "#draft_booking_rules" do
      it "returns booking_rules from draft_data" do
        expect(contract.draft_booking_rules).to eq({ "min_duration" => 2 })
      end

      it "returns empty hash when not set" do
        contract.update!(draft_data: {})
        expect(contract.draft_booking_rules).to eq({})
      end
    end

    describe "#draft_payments" do
      it "returns payments from draft_data" do
        expect(contract.draft_payments).to eq([ { "amount" => 500 } ])
      end

      it "returns empty array when not set" do
        contract.update!(draft_data: {})
        expect(contract.draft_payments).to eq([])
      end
    end

    describe "#draft_payment_structure" do
      it "returns payment_structure from draft_data" do
        expect(contract.draft_payment_structure).to eq("per_hour")
      end

      it "returns default when not set" do
        contract.update!(draft_data: {})
        expect(contract.draft_payment_structure).to eq("flat_fee")
      end
    end

    describe "#draft_payment_config" do
      it "returns payment_config from draft_data" do
        expect(contract.draft_payment_config).to eq({ "hourly_rate" => 50 })
      end

      it "returns empty hash when not set" do
        contract.update!(draft_data: {})
        expect(contract.draft_payment_config).to eq({})
      end
    end

    describe "#draft_ticketing" do
      it "returns ticketing from draft_data" do
        expect(contract.draft_ticketing).to eq({ "tiers" => [ { "name" => "General", "price" => 25.0 } ] })
      end

      it "returns empty hash when not set" do
        contract.update!(draft_data: {})
        expect(contract.draft_ticketing).to eq({})
      end
    end

    describe "#draft_tech" do
      it "returns tech from draft_data" do
        expect(contract.draft_tech).to eq({ "provider" => "us", "hourly_rate" => 25.0, "hours" => 2.0 })
      end

      it "returns empty hash when not set" do
        contract.update!(draft_data: {})
        expect(contract.draft_tech).to eq({})
      end
    end

    describe "#update_draft_step" do
      it "merges step data into draft_data" do
        contract.update_draft_step(:notes, "Some notes")
        expect(contract.draft_data["notes"]).to eq("Some notes")
      end

      it "preserves existing draft_data" do
        contract.update_draft_step(:notes, "Some notes")
        expect(contract.draft_data["bookings"]).to eq([ { "location_id" => 1 } ])
      end
    end
  end

  describe "amend data helpers" do
    let(:contract) { create(:contract, :active) }

    describe "#amend_data" do
      it "returns amend data from draft_data" do
        contract.update!(draft_data: { "amend" => { "notes" => "Amendment" } })
        expect(contract.amend_data).to eq({ "notes" => "Amendment" })
      end

      it "returns empty hash when not set" do
        expect(contract.amend_data).to eq({})
      end
    end

    describe "#update_amend_data" do
      it "sets amend data in draft_data" do
        contract.update_amend_data({ "notes" => "Amendment" })
        expect(contract.amend_data).to eq({ "notes" => "Amendment" })
      end
    end

    describe "#clear_amend_data" do
      it "removes amend data from draft_data" do
        contract.update!(draft_data: { "amend" => { "notes" => "Amendment" }, "other" => "data" })
        contract.clear_amend_data
        expect(contract.amend_data).to eq({})
        expect(contract.draft_data["other"]).to eq("data")
      end
    end
  end

  describe "financial methods" do
    let(:contract) { create(:contract, :active) }

    before do
      create(:contract_payment, contract: contract, direction: "incoming", amount: 1000, status: "pending")
      create(:contract_payment, contract: contract, direction: "incoming", amount: 500, status: "paid")
      create(:contract_payment, contract: contract, direction: "outgoing", amount: 200, status: "pending")
    end

    describe "#total_incoming" do
      it "sums only paid incoming payments (not pending)" do
        expect(contract.total_incoming).to eq(500)
      end
    end

    describe "#total_outgoing" do
      it "sums all outgoing payments" do
        expect(contract.total_outgoing).to eq(200)
      end
    end

    describe "#net_amount" do
      it "calculates paid incoming minus outgoing" do
        expect(contract.net_amount).to eq(300)
      end
    end

    describe "#pending_payments" do
      it "returns only pending payments" do
        expect(contract.pending_payments.count).to eq(2)
      end
    end

    describe "#overdue_payments" do
      it "returns pending payments with past due dates" do
        contract.contract_payments.first.update!(due_date: 1.week.ago)
        expect(contract.overdue_payments.count).to eq(1)
      end
    end
  end

  describe "display helpers" do
    describe "#display_name" do
      it "returns production_name when present" do
        contract = build(:contract, production_name: "Comedy Night", contractor_name: "John Smith")
        expect(contract.display_name).to eq("Comedy Night")
      end

      it "returns contractor_name when production_name is blank" do
        contract = build(:contract, production_name: nil, contractor_name: "John Smith")
        expect(contract.display_name).to eq("John Smith")
      end
    end

    describe "#date_range" do
      it "returns nil when dates are blank" do
        contract = build(:contract, contract_start_date: nil, contract_end_date: nil)
        expect(contract.date_range).to be_nil
      end

      it "returns single date when start equals end" do
        date = Date.new(2024, 6, 15)
        contract = build(:contract, contract_start_date: date, contract_end_date: date)
        expect(contract.date_range).to eq("June 15, 2024")
      end

      it "returns date range when different" do
        contract = build(:contract, contract_start_date: Date.new(2024, 6, 15), contract_end_date: Date.new(2024, 6, 20))
        expect(contract.date_range).to eq("June 15 - June 20, 2024")
      end
    end

    describe "#pending_sales_report?" do
      let(:organization) { create(:organization) }
      let(:production) { create(:production, organization: organization) }
      let(:contract) do
        create(:contract, :active, organization: organization, production: production,
               draft_data: { "payment_config" => { "who_sells_tickets" => "contractor", "settlement_basis" => "revenue_share" } })
      end

      it "is false when the deal isn't contractor-sells revenue-share" do
        org_sells = create(:contract, :active, organization: organization,
               production: create(:production, organization: organization),
               draft_data: { "payment_config" => { "who_sells_tickets" => "org", "settlement_basis" => "revenue_share" } })
        expect(org_sells.pending_sales_report?).to be false
      end

      it "is true when a past show still has unconfirmed sales" do
        create(:show, production: production, date_and_time: 1.week.ago)
        expect(contract.pending_sales_report?).to be true
      end

      it "is false once every past show's sales are confirmed" do
        show = create(:show, production: production, date_and_time: 1.week.ago)
        create(:show_financials, :complete, show: show)
        expect(contract.pending_sales_report?).to be false
      end

      it "ignores future shows that can't be reported yet" do
        create(:show, production: production, date_and_time: 1.week.from_now)
        expect(contract.pending_sales_report?).to be false
      end
    end

    describe "payment model v2 (who sells + settlement basis → direction)" do
      def contract_with(config)
        build(:contract, draft_data: { "payment_config" => config })
      end

      it "Case 1 — we sell, revenue share → we pay them (outgoing)" do
        c = contract_with("who_sells_tickets" => "org", "settlement_basis" => "revenue_share")
        expect(c.settlement_direction).to eq("outgoing")
      end

      it "Case 2 — they sell, revenue share → they pay us (incoming)" do
        c = contract_with("who_sells_tickets" => "contractor", "settlement_basis" => "revenue_share")
        expect(c.settlement_direction).to eq("incoming")
      end

      it "Case 3 — we sell, revenue minus a flat fee → we pay them (outgoing)" do
        c = contract_with("who_sells_tickets" => "org", "settlement_basis" => "revenue_minus_fee")
        expect(c.settlement_direction).to eq("outgoing")
      end

      it "Case 4 — flat rental → they pay us (incoming)" do
        c = contract_with("settlement_basis" => "flat", "flat_fee_direction" => "incoming")
        expect(c.settlement_direction).to eq("incoming")
        expect(c.who_sells_tickets).to be_nil
      end

      it "supports a flat rental we pay out (outgoing)" do
        c = contract_with("settlement_basis" => "flat", "flat_fee_direction" => "outgoing")
        expect(c.settlement_direction).to eq("outgoing")
      end

      # Who sells the tickets and how the deal settles are separate questions:
      # we can run the box office and still just be collecting a rental fee.
      it "we sell the tickets AND they pay us a flat rental → incoming" do
        c = contract_with("who_sells_tickets" => "org", "settlement_basis" => "flat",
                          "flat_fee_direction" => "incoming")

        expect(c.settlement_direction).to eq("incoming")
        expect(c).to be_org_sells_tickets
      end

      it "we sell the tickets AND we pay them a flat guarantee → outgoing" do
        c = contract_with("who_sells_tickets" => "org", "settlement_basis" => "flat",
                          "flat_fee_direction" => "outgoing")

        expect(c.settlement_direction).to eq("outgoing")
      end

      it "they sell the tickets AND still owe us a flat fee → incoming" do
        c = contract_with("who_sells_tickets" => "contractor", "settlement_basis" => "flat",
                          "flat_fee_direction" => "incoming")

        expect(c.settlement_direction).to eq("incoming")
        expect(c).not_to be_org_sells_tickets
      end

      describe "legacy fallback (no v2 keys set)" do
        it "legacy revenue_share reads as they-sell / incoming" do
          c = build(:contract, draft_data: { "payment_structure" => "revenue_share",
                                             "payment_config" => { "revenue_our_share" => 50 } })
          expect(c.settlement_basis).to eq("revenue_share")
          expect(c.who_sells_tickets).to eq("contractor")
          expect(c.settlement_direction).to eq("incoming")
        end

        it "legacy ticket_revenue_minus_fee reads as we-sell / outgoing" do
          c = build(:contract, draft_data: { "payment_structure" => "flat_fee",
                                             "payment_config" => { "flat_fee_direction" => "ticket_revenue_minus_fee",
                                                                   "flat_fee_amount" => 500 } })
          expect(c.settlement_basis).to eq("revenue_minus_fee")
          expect(c.who_sells_tickets).to eq("org")
          expect(c.settlement_direction).to eq("outgoing")
        end
      end

      describe "#flat_fee_entries" do
        it "returns per-event entries with individual prices when set" do
          entries = [ { "amount" => 100, "show_index" => 0 }, { "amount" => 250, "show_index" => 1 } ]
          c = contract_with("settlement_basis" => "flat", "flat_fee_entries" => entries)
          expect(c.flat_fee_entries.map { |e| e["amount"] }).to eq([ 100, 250 ])
        end

        it "falls back to a single whole-contract fee" do
          c = contract_with("settlement_basis" => "flat", "flat_fee_amount" => 750)
          expect(c.flat_fee_entries).to eq([ { "amount" => 750.0, "due_date" => nil, "show_index" => nil } ])
        end
      end
    end

    # How contract money maps into the Money section's revenue/payout totals so it
    # isn't siloed — the gross model (see Contract#money_summary).
    describe "#money_summary" do
      let(:org) { create(:organization) }
      let(:production) { create(:production, organization: org, production_type: "third_party") }

      def contract_for(config)
        c = create(:contract, organization: org, production: production,
          draft_data: { "payment_structure" => config["settlement_basis"] == "revenue_share" ? "revenue_share" : "flat_fee",
                        "payment_config" => config })
        show = create(:show, :online, production: production, date_and_time: 1.week.ago, duration_minutes: 90)
        create(:show_financials, :complete, show: show, ticket_revenue: 1000.0, other_revenue: 0.0)
        c
      end

      it "we sell (Case 1): full revenue in, contractor share out" do
        c = contract_for("who_sells_tickets" => "org", "settlement_basis" => "revenue_share",
                         "revenue_our_share" => 30, "revenue_their_share" => 70)
        expect(c.money_summary).to eq(money_in: 1000.0, money_out: 700.0)
      end

      it "they sell (Case 2): only our cut in, nothing out" do
        c = contract_for("who_sells_tickets" => "contractor", "settlement_basis" => "revenue_share",
                         "revenue_our_share" => 30, "revenue_their_share" => 70)
        expect(c.money_summary).to eq(money_in: 300.0, money_out: 0.0)
      end

      it "flat deal: the contract's own payments by direction" do
        c = create(:contract, organization: org, production: production,
          draft_data: { "payment_structure" => "flat_fee", "payment_config" => { "flat_fee_direction" => "incoming" } })
        create(:contract_payment, contract: c, direction: "incoming", amount: 500)
        create(:contract_payment, contract: c, direction: "outgoing", amount: 120)

        expect(c.money_summary).to eq(money_in: 500.0, money_out: 120.0)
      end
    end
  end

  describe "#execute_by_signature!" do
    it "enqueues the manager notification when the counterparty signs" do
      contract = create(:contract, signing_mode: :esign, signing_state: :out_for_signature)
      allow(GenerateContractPdfJob).to receive(:perform_later)

      expect(ContractSignedNotificationJob).to receive(:perform_later).with(contract.id)

      contract.execute_by_signature!(signer_name: "Dan", signer_email: "dan@example.com",
        request: double(remote_ip: "1.2.3.4", user_agent: "spec"))
    end
  end

  describe "inline license schedule" do
    let(:org) { create(:organization) }
    let(:location) { create(:location, organization: org) }
    let(:mainstage) { location.location_spaces.create!(name: "The Mainstage") }

    # One evening booking with a distinct event window, on a known stage.
    def booking(date:, space: mainstage, event_type: "show")
      day = Date.parse(date)
      {
        "starts_at" => day.to_time.change(hour: 18).iso8601,
        "ends_at" => day.to_time.change(hour: 23).iso8601,
        "event_starts_at" => day.to_time.change(hour: 20).iso8601,
        "event_ends_at" => day.to_time.change(hour: 22).iso8601,
        "location_id" => location.id,
        "location_space_id" => space.id,
        "event_type" => event_type
      }
    end

    describe "#license_schedule_html" do
      it "shows the full booked slot (rental start/end), not the show's own window" do
        contract = create(:contract, organization: org, production_name: "Late Night Revue",
          draft_data: { "bookings" => [ booking(date: "2026-03-06") ] })

        # Structured row is unambiguous: booked 6–11 PM even though the show is 8–10.
        row = contract.send(:license_schedule_rows).first
        expect(row[:start]).to eq("6:00 PM")
        expect(row[:end]).to eq("11:00 PM")

        html = contract.send(:license_schedule_html)
        expect(html).to include("<th>Dates</th>", "<th>Stage</th>", "<th>Rent</th>")
        expect(html).to include("Fri Mar 6, 2026", "6:00 PM", "11:00 PM", "The Mainstage")
      end

      it "uses the production name when the booking's event_type is the generic 'show'" do
        contract = create(:contract, organization: org, production_name: "Late Night Revue",
          draft_data: { "bookings" => [ booking(date: "2026-03-06") ] })

        expect(contract.send(:license_schedule_html)).to include("Late Night Revue")
      end

      it "labels the stage 'Entire venue' when no space is set" do
        b = booking(date: "2026-03-06").except("location_space_id")
        contract = create(:contract, organization: org, draft_data: { "bookings" => [ b ] })

        expect(contract.send(:license_schedule_html)).to include("Entire venue")
      end

      it "shows an empty-state row when there are no bookings" do
        contract = create(:contract, organization: org, draft_data: { "bookings" => [] })

        expect(contract.send(:license_schedule_html)).to include("Dates to be confirmed")
      end

      context "rent column" do
        it "matches a dated payment to its booking by date" do
          contract = create(:contract, organization: org,
            draft_data: {
              "bookings" => [ booking(date: "2026-03-06") ],
              "payments" => [ { "amount" => 500, "due_date" => "2026-03-06", "description" => "Mar 6 event" } ]
            })

          expect(contract.send(:license_schedule_html)).to include("$500.00")
        end

        it "falls back to the flat per-event amount when no dated payment matches" do
          contract = create(:contract, organization: org,
            draft_data: {
              "bookings" => [ booking(date: "2026-03-06") ],
              "payment_structure" => "per_event",
              "payment_config" => { "per_event_amount" => 350 }
            })

          expect(contract.send(:license_schedule_html)).to include("$350.00")
        end

        it "shows the fee (never a dash/TBD) for a flat-fee deal" do
          contract = create(:contract, organization: org,
            draft_data: {
              "bookings" => [ booking(date: "2026-03-06") ],
              "payment_structure" => "flat_fee",
              "payment_config" => { "flat_fee_amount" => 1000 }
            })

          html = contract.send(:license_schedule_html)
          expect(html).to include("$1000.00")
          expect(html).not_to include("TBD")
          expect(html).not_to include("—")
        end

        it "phrases a revenue-share deal as the venue's cut, not TBD" do
          contract = create(:contract, organization: org,
            draft_data: {
              "bookings" => [ booking(date: "2026-03-06") ],
              "payment_structure" => "revenue_share",
              "payment_config" => { "revenue_our_share" => 50, "revenue_source" => "ticket_sales" }
            })

          html = contract.send(:license_schedule_html)
          expect(html).to include("50% of ticket sales")
          expect(html).not_to include("TBD")
        end

        it "ignores a TBD revenue-share payment row and states the share instead" do
          contract = create(:contract, organization: org,
            draft_data: {
              "bookings" => [ booking(date: "2026-03-06") ],
              "payment_structure" => "revenue_share",
              "payment_config" => { "revenue_our_share" => 60, "revenue_source" => "door_sales" },
              "payments" => [ { "amount" => 0, "amount_tbd" => true, "due_date" => "2026-03-06" } ]
            })

          html = contract.send(:license_schedule_html)
          expect(html).to include("60% of door sales")
          expect(html).not_to include("TBD")
        end
      end

      context "payment-schedule sub-grid (below the main grid)" do
        it "adds a payment schedule when money is due on dates beyond the bookings" do
          contract = create(:contract, organization: org,
            draft_data: {
              "bookings" => [ booking(date: "2026-03-06") ],
              "payments" => [
                { "description" => "Balance", "amount" => 500, "due_date" => "2026-03-06" },
                { "description" => "Deposit", "amount" => 500, "due_date" => "2026-02-06" }
              ]
            })

          html = contract.send(:license_schedule_html)

          expect(html).to include("Payment schedule")
          expect(html).to include("Deposit", "Balance", "Feb 6, 2026")
          # Sorted oldest first: the deposit (due Feb) row precedes the balance (due Mar).
          expect(html.index("Deposit")).to be < html.index("Balance")
        end

        it "omits the sub-grid for per-event rent that already shows in the Rent column" do
          contract = create(:contract, organization: org,
            draft_data: {
              "bookings" => [ booking(date: "2026-03-06") ],
              "payment_structure" => "per_event",
              "payments" => [ { "description" => "Mar 6 event", "amount" => 350, "due_date" => "2026-03-06" } ]
            })

          expect(contract.send(:license_schedule_html)).not_to include("Payment schedule")
        end

        it "omits the sub-grid for a pure revenue split (nothing concrete is due)" do
          contract = create(:contract, organization: org,
            draft_data: {
              "bookings" => [ booking(date: "2026-03-06") ],
              "payment_structure" => "revenue_share",
              "payment_config" => { "revenue_our_share" => 50 },
              "payments" => [ { "amount" => 0, "amount_tbd" => true, "due_date" => "2026-03-20" } ]
            })

          expect(contract.send(:license_schedule_html)).not_to include("Payment schedule")
        end
      end
    end

    describe "#license_services_html and the {{services}} token" do
      let(:contract_with_services) do
        create(:contract, organization: org,
          draft_data: {
            "bookings" => [ booking(date: "2026-03-06") ],
            "services" => [
              { "name" => "Sound technician", "quantity" => 2, "unit_price" => 25, "unit" => "hourly" },
              { "name" => "Stagehand", "quantity" => 1, "unit_price" => 20, "unit" => "hourly" }
            ]
          })
      end

      it "lists the service line items with quantity and rate" do
        html = contract_with_services.send(:license_services_html)

        expect(html).to include("Sound technician × 2 — $25.00/hr")
        expect(html).to include("Stagehand — $20.00/hr")
      end

      it "renders nothing when the contract has no services (no orphan header)" do
        contract = create(:contract, organization: org, draft_data: { "bookings" => [] })

        expect(contract.send(:license_services_html)).to eq("")
      end

      it "fills the {{services}} token inline and suppresses the appended Deal Terms" do
        template = ContractTemplate.new(organization: org, name: "Svc", version: 1)
        template.content = "<div>Wording.</div>{{services}}"
        template.save!

        doc = contract_with_services.render_document_for(template)

        expect(doc).to include("Sound technician")
        expect(doc).not_to include("{{services}}")
        expect(doc).not_to include("Deal Terms")
      end
    end

    describe "#render_document_for with the {{license_schedule}} token" do
      let(:contract) do
        create(:contract, organization: org, contractor_name: "Local Troupe", production_name: "Late Night Revue",
          draft_data: {
            "bookings" => [ booking(date: "2026-03-06") ],
            "payment_structure" => "per_event",
            "payment_config" => { "per_event_amount" => 350 }
          })
      end

      def template_with(body)
        t = ContractTemplate.new(organization: org, name: "T", version: 1)
        t.content = body
        t.save!
        t
      end

      it "fills the grid inline and does NOT append the Deal Terms block" do
        template = template_with("<div><strong>1.1</strong></div><div>{{license_schedule}}</div>")

        doc = contract.render_document_for(template)

        expect(doc).to include("<table>", "The Mainstage", "$350.00")
        expect(doc).not_to include("Deal Terms")
        expect(doc).not_to include("{{license_schedule}}") # token consumed
      end

      it "appends the Deal Terms schedule for templates without the token" do
        template = template_with("<div>Plain wording, no inline schedule.</div>")

        doc = contract.render_document_for(template)

        expect(doc).to include("Deal Terms")
      end
    end

    describe "the Stars & Garters residency template end to end" do
      let(:template) do
        t = ContractTemplate.new(organization: org, name: StarsAndGartersResidencyTemplate::TEMPLATE_NAME, version: 1)
        t.content = StarsAndGartersResidencyTemplate::CONTENT
        t.save!
        t
      end
      let(:contract) do
        create(:contract, organization: org, contract_template: template,
          contractor_name: "Local Troupe", production_name: "Late Night Revue",
          draft_data: {
            "bookings" => [ booking(date: "2026-03-06") ],
            "payment_structure" => "per_event",
            "payment_config" => { "per_event_amount" => 350 },
            "services" => [ { "name" => "Sound technician", "quantity" => 2, "unit_price" => 25, "unit" => "hourly" } ]
          })
      end

      it "renders the boilerplate, fills the grid + services inline, and drops no raw token" do
        doc = contract.render_signable_document

        expect(doc).to include("STARS &amp; GARTERS RESIDENCY AGREEMENT")
        expect(doc).to include("Local Troupe") # {{contractor_name}} filled
        expect(doc).to include("The Mainstage", "$350.00") # {{license_schedule}} grid
        expect(doc).to include("Sound technician × 2 — $25.00/hr") # {{services}} filled
        expect(doc).not_to include("{{") # every token consumed
        expect(doc).not_to include("Deal Terms") # inline schedule suppresses the append
      end

      it "generates a PDF without raising (the nested-table walker handles the grid)" do
        bytes = ContractPdf.new(contract).render

        expect(bytes).to be_present
        expect(bytes[0, 4]).to eq("%PDF")
      end
    end
  end
end
