# frozen_string_literal: true

require "rails_helper"

# "We cast people in this production" / "We don't cast people in this
# production": changing the answer brings the coming dates into line with
# it, and removes nobody.
RSpec.describe CastingAnswer do
  let(:production) { create(:production) }
  let!(:role) { create(:role, production: production) }
  let!(:show) { create(:show, production: production, date_and_time: 2.weeks.from_now) }
  let!(:cast_show) { create(:show, production: production, date_and_time: 3.weeks.from_now) }
  let!(:rehearsal) { create(:show, production: production, event_type: "rehearsal", date_and_time: 1.week.from_now) }
  let!(:past_show) { create(:show, production: production, date_and_time: 2.weeks.ago) }
  let!(:assignment) { create(:show_person_role_assignment, show: cast_show, role: role) }

  describe ".off!" do
    it "switches casting off on the coming dates nobody is cast in, and leaves the rest" do
      expect(described_class.off!(production)).to be(true)

      expect(production.reload.casts_people).to be(false)
      expect(show.reload.casting_enabled).to be(false)
      expect(cast_show.reload.casting_enabled).to be(true)
      expect(cast_show.show_person_role_assignments).to contain_exactly(assignment)
      expect(past_show.reload.casting_enabled).to be(true)
    end

    it "does nothing the second time" do
      described_class.off!(production)
      expect(described_class.off!(production)).to be(false)
    end
  end

  describe ".on!" do
    before { described_class.off!(production) }

    it "switches casting on for the coming dates of a kind that starts with it, and leaves rehearsals off" do
      described_class.on!(production)

      expect(production.reload.casts_people).to be(true)
      expect(show.reload.casting_enabled).to be(true)
      expect(rehearsal.reload.casting_enabled).to be(false)
    end
  end

  describe ".choose_rule!" do
    it "casts all performances: shows on, the rehearsal off" do
      rehearsal.update_columns(casting_enabled: true)
      described_class.choose_rule!(production, matching: "all")

      expect(production.reload.casting_event_matching).to eq("all")
      expect([ show, cast_show, rehearsal ].map { |date| date.reload.casting_enabled }).to eq([ true, true, false ])
      expect(past_show.reload.casting_enabled).to be(true)
    end

    it "casts only the kinds of event given, with nobody removed" do
      described_class.choose_rule!(production, matching: "event_types", event_types: %w[rehearsal nonsense])

      expect(production.reload).to have_attributes(casting_event_matching: "event_types", casting_event_type_filter: %w[rehearsal])
      expect([ show, cast_show, rehearsal ].map { |date| date.reload.casting_enabled }).to eq([ false, false, true ])
      expect(cast_show.show_person_role_assignments.count).to eq(1)
    end

    it "casts only the dates picked" do
      described_class.choose_rule!(production, matching: "manual", show_ids: [ cast_show.id.to_s ])

      expect(production.reload.casting_event_matching).to eq("manual")
      expect([ show, cast_show, rehearsal ].map { |date| date.reload.casting_enabled }).to eq([ false, true, false ])
    end
  end

  describe ".on!, by the production's choice" do
    it "switches on only what the choice covers" do
      production.update!(casting_event_matching: "event_types", casting_event_type_filter: %w[rehearsal])
      described_class.off!(production)
      described_class.on!(production)

      expect(rehearsal.reload.casting_enabled).to be(true)
      expect(show.reload.casting_enabled).to be(false)
    end
  end

  describe ".choose_dates!" do
    it "has casting on for the chosen coming dates and off for the others, with nobody removed" do
      described_class.choose_dates!(production, [ rehearsal.id.to_s ])

      expect(rehearsal.reload.casting_enabled).to be(true)
      expect(show.reload.casting_enabled).to be(false)
      expect(cast_show.reload.casting_enabled).to be(false)
      expect(cast_show.show_person_role_assignments.count).to eq(1)
      expect(past_show.reload.casting_enabled).to be(true)
    end

    it "ignores a date that isn't the production's" do
      elsewhere = create(:show, event_type: "rehearsal", date_and_time: 1.week.from_now)

      described_class.choose_dates!(production, [ elsewhere.id ])
      expect(elsewhere.reload.casting_enabled).to be(false)
    end
  end
end
