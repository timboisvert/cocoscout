# frozen_string_literal: true

require "rails_helper"

RSpec.describe PayrollRun, type: :model do
  describe "constants" do
    it "defines STATUSES" do
      expect(described_class::STATUSES).to eq(%w[pending processing completed cancelled])
    end
  end

  describe "associations" do
    let(:organization) { create(:organization) }
    let(:user) { create(:user) }
    let(:run) { create(:payroll_run, organization: organization, created_by: user) }

    it "belongs to organization" do
      expect(run).to respond_to(:organization)
      expect(run.organization).to be_present
    end

    it "belongs to payroll_schedule (optional)" do
      expect(run).to respond_to(:payroll_schedule)
    end

    it "belongs to created_by" do
      expect(run).to respond_to(:created_by)
      expect(run.created_by).to be_present
    end

    it "belongs to processed_by (optional)" do
      expect(run).to respond_to(:processed_by)
    end

    it "has many payroll_line_items" do
      expect(run).to respond_to(:payroll_line_items)
    end

    it "has many people through payroll_line_items" do
      expect(run).to respond_to(:people)
    end

    it "has many show_payout_line_items through payroll_line_items" do
      expect(run).to respond_to(:show_payout_line_items)
    end
  end

  describe "validations" do
    let(:organization) { create(:organization) }
    let(:user) { create(:user) }

    it "requires period_start" do
      run = build(:payroll_run, organization: organization, created_by: user, period_start: nil)
      expect(run).not_to be_valid
      expect(run.errors[:period_start]).to be_present
    end

    it "requires period_end" do
      run = build(:payroll_run, organization: organization, created_by: user, period_end: nil)
      expect(run).not_to be_valid
      expect(run.errors[:period_end]).to be_present
    end

    describe "status inclusion" do
      it "validates status is in STATUSES" do
        run = build(:payroll_run, status: "invalid")
        expect(run).not_to be_valid
        expect(run.errors[:status]).to include("is not included in the list")
      end

      it "accepts valid statuses" do
        described_class::STATUSES.each do |status|
          run = build(:payroll_run, status: status)
          expect(run).to be_valid
        end
      end
    end

    describe "period_end_after_start" do
      it "requires period_end to be after period_start" do
        run = build(:payroll_run, period_start: Date.current, period_end: 1.week.ago)
        expect(run).not_to be_valid
        expect(run.errors[:period_end]).to include("must be after period start")
      end
    end
  end

  describe "scopes" do
    let(:organization) { create(:organization) }
    let(:user) { create(:user) }
    let!(:pending_run) { create(:payroll_run, organization: organization, created_by: user, status: "pending") }
    let!(:processing_run) { create(:payroll_run, organization: organization, created_by: user, status: "processing") }
    let!(:completed_run) { create(:payroll_run, organization: organization, created_by: user, status: "completed") }
    let!(:cancelled_run) { create(:payroll_run, organization: organization, created_by: user, status: "cancelled") }

    describe ".pending" do
      it "returns only pending runs" do
        expect(described_class.pending).to contain_exactly(pending_run)
      end
    end

    describe ".processing" do
      it "returns only processing runs" do
        expect(described_class.processing).to contain_exactly(processing_run)
      end
    end

    describe ".completed" do
      it "returns only completed runs" do
        expect(described_class.completed).to contain_exactly(completed_run)
      end
    end

    describe ".cancelled" do
      it "returns only cancelled runs" do
        expect(described_class.cancelled).to contain_exactly(cancelled_run)
      end
    end

    describe ".active" do
      it "returns pending and processing runs" do
        expect(described_class.active).to contain_exactly(pending_run, processing_run)
      end
    end

    describe ".by_period" do
      it "orders by period_end descending" do
        # Use a separate organization to isolate from other test data
        org2 = create(:organization)
        user2 = create(:user)
        oldest = create(:payroll_run, organization: org2, created_by: user2, period_start: 5.weeks.ago, period_end: 4.weeks.ago)
        newest = create(:payroll_run, organization: org2, created_by: user2, period_start: 2.weeks.ago, period_end: 1.week.ago)
        middle = create(:payroll_run, organization: org2, created_by: user2, period_start: 4.weeks.ago, period_end: 3.weeks.ago)

        result = described_class.where(organization: org2).by_period.to_a
        expect(result).to eq([ newest, middle, oldest ])
      end
    end
  end

  describe "status predicates" do
    let(:run) { build(:payroll_run) }

    describe "#pending?" do
      it "returns true when status is pending" do
        run.status = "pending"
        expect(run.pending?).to be true
      end

      it "returns false otherwise" do
        run.status = "completed"
        expect(run.pending?).to be false
      end
    end

    describe "#processing?" do
      it "returns true when status is processing" do
        run.status = "processing"
        expect(run.processing?).to be true
      end
    end

    describe "#completed?" do
      it "returns true when status is completed" do
        run.status = "completed"
        expect(run.completed?).to be true
      end
    end

    describe "#cancelled?" do
      it "returns true when status is cancelled" do
        run.status = "cancelled"
        expect(run.cancelled?).to be true
      end
    end
  end

  describe "#can_process?" do
    let(:organization) { create(:organization) }
    let(:user) { create(:user) }
    let(:person) { create(:person) }

    it "returns true when pending and has line items" do
      run = create(:payroll_run, organization: organization, created_by: user, status: "pending")
      create(:payroll_line_item, payroll_run: run, person: person)
      expect(run.can_process?).to be true
    end

    it "returns false when pending but no line items" do
      run = create(:payroll_run, organization: organization, created_by: user, status: "pending")
      expect(run.can_process?).to be false
    end

    it "returns false when not pending" do
      run = create(:payroll_run, organization: organization, created_by: user, status: "completed")
      create(:payroll_line_item, payroll_run: run, person: person)
      expect(run.can_process?).to be false
    end
  end

  describe "#can_cancel?" do
    let(:run) { build(:payroll_run) }

    it "returns true when pending" do
      run.status = "pending"
      expect(run.can_cancel?).to be true
    end

    it "returns false when not pending" do
      run.status = "completed"
      expect(run.can_cancel?).to be false
    end
  end

  describe "#period_label" do
    let(:organization) { create(:organization) }
    let(:user) { create(:user) }

    context "when same month" do
      it "returns compact format" do
        run = build(:payroll_run, organization: organization, created_by: user,
          period_start: Date.new(2024, 6, 1), period_end: Date.new(2024, 6, 15))
        expect(run.period_label).to eq("Jun 1 – 15, 2024")
      end
    end

    context "when different months" do
      it "returns full format" do
        run = build(:payroll_run, organization: organization, created_by: user,
          period_start: Date.new(2024, 5, 15), period_end: Date.new(2024, 6, 15))
        expect(run.period_label).to eq("May 15, 2024 – Jun 15, 2024")
      end
    end
  end

  describe "lifecycle methods" do
    let(:organization) { create(:organization) }
    let(:user) { create(:user) }
    let(:person) { create(:person) }

    describe "#start_processing!" do
      let(:run) { create(:payroll_run, organization: organization, created_by: user, status: "pending") }

      context "when pending" do
        it "changes status to processing" do
          run.start_processing!(user)
          expect(run.reload.status).to eq("processing")
        end

        it "sets processed_by" do
          run.start_processing!(user)
          expect(run.reload.processed_by).to eq(user)
        end
      end

      context "when not pending" do
        before { run.update!(status: "completed") }

        it "returns false" do
          expect(run.start_processing!(user)).to be false
        end

        it "does not change status" do
          run.start_processing!(user)
          expect(run.reload.status).to eq("completed")
        end
      end
    end

    describe "#complete!" do
      let(:run) { create(:payroll_run, organization: organization, created_by: user, status: "processing", processed_by: user) }

      context "when processing" do
        it "changes status to completed" do
          run.complete!
          expect(run.reload.status).to eq("completed")
        end

        it "sets processed_at" do
          run.complete!
          expect(run.reload.processed_at).to be_present
        end
      end

      context "when pending" do
        before { run.update!(status: "pending") }

        it "changes status to completed" do
          run.complete!
          expect(run.reload.status).to eq("completed")
        end
      end

      context "when already completed" do
        before { run.update!(status: "completed") }

        it "returns false" do
          expect(run.complete!).to be false
        end
      end
    end

    describe "#cancel!" do
      context "when pending" do
        let(:run) { create(:payroll_run, organization: organization, created_by: user, status: "pending") }

        it "changes status to cancelled" do
          run.cancel!
          expect(run.reload.status).to eq("cancelled")
        end

        it "destroys all payroll line items" do
          create(:payroll_line_item, payroll_run: run, person: person)
          expect { run.cancel! }.to change { run.payroll_line_items.count }.to(0)
        end
      end

      context "when processing" do
        let(:run) { create(:payroll_run, organization: organization, created_by: user, status: "processing", processed_by: user) }

        it "changes status to cancelled" do
          run.cancel!
          expect(run.reload.status).to eq("cancelled")
        end
      end

      context "when completed" do
        let(:run) { create(:payroll_run, organization: organization, created_by: user, status: "completed") }

        it "returns false" do
          expect(run.cancel!).to be false
        end

        it "does not change status" do
          run.cancel!
          expect(run.reload.status).to eq("completed")
        end
      end
    end
  end

  describe "#calculated_total_amount" do
    let(:organization) { create(:organization) }
    let(:user) { create(:user) }
    let(:run) { create(:payroll_run, organization: organization, created_by: user) }
    let(:person1) { create(:person) }
    let(:person2) { create(:person) }
    let(:pli1) { create(:payroll_line_item, payroll_run: run, person: person1) }
    let(:pli2) { create(:payroll_line_item, payroll_run: run, person: person2) }

    it "sums net amounts from all payroll line items" do
      production = create(:production, organization: organization)
      show = create(:show, production: production)
      show_payout = create(:show_payout, show: show)
      create(:show_payout_line_item, show_payout: show_payout, payee: person1, amount: 100, payroll_line_item: pli1)
      create(:show_payout_line_item, show_payout: show_payout, payee: person2, amount: 50, payroll_line_item: pli2)

      expect(run.calculated_total_amount).to eq(150)
    end
  end
end
