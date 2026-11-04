# frozen_string_literal: true

require "rails_helper"

RSpec.describe PersonHistoryFeed, "shift vacancies" do
  let(:org) { create(:organization, owner: create(:user), name: "Stars & Garters") }
  let(:shift) { create(:shift, organization: org, house_role: create(:house_role, organization: org, name: "Bar"), starts_at: 1.week.from_now.change(hour: 19), ends_at: 1.week.from_now.change(hour: 23)) }
  let(:dana) { create(:person, name: "Dana Morris") }
  let(:priya) { create(:person, name: "Priya Kaur") }

  it "lists the shift they couldn't make for the dropper, and the cover for who took it" do
    assignment = shift.shift_assignments.create!(person: dana, position: 1).tap { |a| a.decline!(reason: "Sick") }
    assignment.active_vacancy.fill!(priya, accepted: true)

    dropped = described_class.new(dana).page.find { |e| e.kind == :vacancy_created }
    expect(dropped.title).to eq("Said they can't make a shift")
    expect(dropped.subtitle).to eq("Stars & Garters")
    expect(dropped.details).to include("Bar", "“Sick”")

    covered = described_class.new(priya).page.find { |e| e.kind == :vacancy_filled }
    expect(covered.title).to eq("Covered a shift")
    expect(covered.details).to include("Bar", "for Dana Morris")
  end
end
