# frozen_string_literal: true

require "rails_helper"

RSpec.describe EventLinkage, type: :model do
  describe "associations" do
    it "belongs to production" do
      linkage = build(:production).event_linkages.build
      expect(linkage).to respond_to(:production)
    end

    it "belongs to primary_show optionally" do
      production = create(:production)
      linkage = EventLinkage.create!(production: production)
      expect(linkage.primary_show).to be_nil
    end

    it "has many shows" do
      production = create(:production)
      linkage = EventLinkage.create!(production: production)
      show = create(:show, production: production, event_linkage: linkage)
      expect(linkage.shows).to include(show)
    end
  end

  describe "validations" do
    it "requires production" do
      linkage = EventLinkage.new(production: nil)
      expect(linkage).not_to be_valid
    end
  end

  describe "#all_shows_chronological" do
    let(:production) { create(:production) }
    let(:linkage) { EventLinkage.create!(production: production) }

    let!(:show1) { create(:show, production: production, event_linkage: linkage, date_and_time: 2.days.from_now) }
    let!(:show2) { create(:show, production: production, event_linkage: linkage, date_and_time: 1.day.from_now) }
    let!(:show3) { create(:show, production: production, event_linkage: linkage, date_and_time: 3.days.from_now) }

    it "returns shows in chronological order" do
      expect(linkage.all_shows_chronological.pluck(:id)).to eq([ show2.id, show1.id, show3.id ])
    end
  end

  describe "#resolved_primary_show" do
    let(:production) { create(:production) }
    let(:linkage) { EventLinkage.create!(production: production) }

    context "when primary_show is set" do
      let!(:primary) { create(:show, production: production) }

      before do
        linkage.update!(primary_show: primary)
      end

      it "returns the explicit primary show" do
        expect(linkage.resolved_primary_show).to eq(primary)
      end
    end

    context "when primary_show is not set" do
      let!(:show1) { create(:show, production: production, event_linkage: linkage, linkage_role: :sibling, date_and_time: 2.days.from_now) }
      let!(:show2) { create(:show, production: production, event_linkage: linkage, linkage_role: :sibling, date_and_time: 1.day.from_now) }

      it "returns the first sibling by date" do
        expect(linkage.resolved_primary_show).to eq(show2)
      end
    end
  end

  describe "#finalize_casting!" do
    let(:production) { create(:production) }
    let(:linkage) { EventLinkage.create!(production: production) }
    let!(:show1) { create(:show, production: production, event_linkage: linkage) }
    let!(:show2) { create(:show, production: production, event_linkage: linkage) }

    it "sets casting_finalized_at on all linked shows" do
      linkage.finalize_casting!

      expect(show1.reload.casting_finalized_at).to be_present
      expect(show2.reload.casting_finalized_at).to be_present
    end
  end

  describe "#reopen_casting!" do
    let(:production) { create(:production) }
    let(:linkage) { EventLinkage.create!(production: production) }
    let!(:show) { create(:show, production: production, event_linkage: linkage, casting_finalized_at: Time.current) }

    it "clears casting_finalized_at on all linked shows" do
      linkage.reopen_casting!

      expect(show.reload.casting_finalized_at).to be_nil
    end
  end

  describe "#casting_finalized?" do
    let(:production) { create(:production) }
    let(:linkage) { EventLinkage.create!(production: production) }
    let!(:show1) { create(:show, production: production, event_linkage: linkage, casting_finalized_at: Time.current) }
    let!(:show2) { create(:show, production: production, event_linkage: linkage) }

    it "returns false when any show has nil casting_finalized_at" do
      expect(linkage.casting_finalized?).to be false
    end

    it "returns true when all shows have casting_finalized_at" do
      show2.update!(casting_finalized_at: Time.current)
      expect(linkage.casting_finalized?).to be true
    end
  end

  describe "#display_name" do
    let(:production) { create(:production) }
    let(:linkage) { EventLinkage.create!(production: production) }

    context "with explicit name" do
      before { linkage.update!(name: "Weekend Shows") }

      it "returns the explicit name" do
        expect(linkage.display_name).to eq("Weekend Shows")
      end
    end

    context "without explicit name" do
      context "with no sibling shows" do
        it "returns default text" do
          expect(linkage.display_name).to eq("Linked Events")
        end
      end

      context "with one sibling show" do
        let!(:show) do
          create(:show, production: production, event_linkage: linkage,
                        linkage_role: :sibling, date_and_time: Time.zone.local(2025, 3, 15, 19, 0))
        end

        it "returns formatted date" do
          expect(linkage.display_name).to eq("Mar 15")
        end
      end

      context "with multiple sibling shows in same month" do
        before do
          create(:show, production: production, event_linkage: linkage,
                        linkage_role: :sibling, date_and_time: Time.zone.local(2025, 3, 15, 19, 0))
          create(:show, production: production, event_linkage: linkage,
                        linkage_role: :sibling, date_and_time: Time.zone.local(2025, 3, 20, 19, 0))
        end

        it "returns date range within month" do
          expect(linkage.display_name).to eq("Mar 15-20")
        end
      end

      context "with multiple sibling shows spanning months" do
        before do
          create(:show, production: production, event_linkage: linkage,
                        linkage_role: :sibling, date_and_time: Time.zone.local(2025, 3, 30, 19, 0))
          create(:show, production: production, event_linkage: linkage,
                        linkage_role: :sibling, date_and_time: Time.zone.local(2025, 4, 5, 19, 0))
        end

        it "returns date range with months" do
          expect(linkage.display_name).to eq("Mar 30 - Apr 5")
        end
      end
    end
  end
end
