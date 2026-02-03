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

    it "has many productions" do
      expect(contract).to respond_to(:productions)
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
          expect { contract.activate! }.to change { contract.productions.count }.by(1)
        end

        it "creates shows for each space rental" do
          contract.activate!
          production = contract.productions.first
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
        "services" => [ { "name" => "Sound" } ]
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

    describe "#draft_services" do
      it "returns services from draft_data" do
        expect(contract.draft_services).to eq([ { "name" => "Sound" } ])
      end

      it "returns empty array when not set" do
        contract.update!(draft_data: {})
        expect(contract.draft_services).to eq([])
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
      it "sums all incoming payments" do
        expect(contract.total_incoming).to eq(1500)
      end
    end

    describe "#total_outgoing" do
      it "sums all outgoing payments" do
        expect(contract.total_outgoing).to eq(200)
      end
    end

    describe "#net_amount" do
      it "calculates incoming minus outgoing" do
        expect(contract.net_amount).to eq(1300)
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
  end
end
