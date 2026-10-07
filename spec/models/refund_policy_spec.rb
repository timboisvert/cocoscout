# frozen_string_literal: true

require "rails_helper"

# The refund policy a box office (or a production) declares, and the words
# buyers see (Round 10, 2026-10-07).
RSpec.describe RefundPolicy do
  let(:show) { instance_double(Show, date_and_time: Time.zone.local(2026, 11, 6, 21, 0)) }

  it "words each choice for buyers, cancellations always refunded" do
    expect(described_class.new(kind: "window", hours: 24).words).to eq("Refunds up to 24 hours before the show. Fees aren't refunded. If a show is canceled, you get everything back.")
    expect(described_class.new(kind: "window", hours: 0, fees: true).words).to eq("Refunds until the show starts. Fees are refunded too. If a show is canceled, you get everything back.")
    expect(described_class.new(kind: "window", hours: 168).short_words).to eq("Refunds up to 7 days before the show")
    expect(described_class.new(kind: "window", hours: 48).short_words).to eq("Refunds up to 48 hours before the show")
    expect(described_class.new(kind: "window", hours: 72).short_words).to eq("Refunds up to 3 days before the show")
    expect(described_class.new(kind: "none").words).to eq("All sales are final: no refunds. If a show is canceled, you get everything back.")
    expect(described_class.new(kind: "case_by_case", contact: "box@sg.example", note: "Exchanges welcome.").words)
      .to eq("Refunds are case by case: ask box@sg.example. Fees aren't refunded. If a show is canceled, you get everything back. Exchanges welcome.")
  end

  it "ends a window that many hours before the show" do
    expect(described_class.new(kind: "window", hours: 24).deadline(show)).to eq(Time.zone.local(2026, 11, 5, 21, 0))
    expect(described_class.new(kind: "window", hours: 0).deadline(show)).to eq(show.date_and_time)
    expect(described_class.new(kind: "none").deadline(show)).to be_nil
  end

  it "picks the more generous of two policies, fees back if either says so" do
    day = described_class.new(kind: "window", hours: 24)
    week = described_class.new(kind: "window", hours: 168, fees: true)
    none = described_class.new(kind: "none")
    ask = described_class.new(kind: "case_by_case")

    expect(described_class.more_generous(week, day)).to have_attributes(kind: "window", hours: 24, fees: true)
    expect(described_class.more_generous(none, week)).to have_attributes(kind: "window", hours: 168)
    expect(described_class.more_generous(ask, day).kind).to eq("case_by_case")
    expect(described_class.more_generous(nil, day)).to eq(day)
  end

  it "turns the settings cards into columns and back" do
    expect(described_class.attributes_for("window_168")).to eq(refund_policy: "window", refund_window_hours: 168)
    expect(described_class.attributes_for("custom", "10")).to eq(refund_policy: "window", refund_window_hours: 240)
    expect(described_class.attributes_for("custom", "999")).to eq(refund_policy: "window", refund_window_hours: 365 * 24)
    expect(described_class.attributes_for("none")).to eq(refund_policy: "none")
    expect(described_class.attributes_for("window_5")).to be_nil
    expect(described_class.choice_for("window", 240)).to eq("custom")
    expect(described_class.choice_for("window", 24)).to eq("window_24")
    expect(described_class.choice_for("case_by_case", 24)).to eq("case_by_case")
  end

  it "reads a production's own policy over the box office's, blank fields following the box office" do
    org = create(:organization, :pro)
    profile = TicketingProfile.for(org)
    profile.update!(refund_policy: "window", refund_window_hours: 48, refund_fees: true, support_email: "box@sg.example")
    setup = ProductionTicketing.for(create(:production, organization: org))

    expect(described_class.of_setup(setup, profile)).to have_attributes(kind: "window", hours: 48, fees: true)
    setup.update!(refund_policy: "none")
    expect(described_class.of_setup(setup, profile)).to have_attributes(kind: "none", fees: true, contact: "box@sg.example")
  end
end
