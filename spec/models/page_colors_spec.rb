# frozen_string_literal: true

require "rails_helper"

# The pages' colors (Tim, 2026-11-18): set on the box office, overridden all
# four together by a production, then by a date.
RSpec.describe PageColors do
  let(:org) { create(:organization, :pro) }
  let(:profile) { TicketingProfile.for(org) }
  let(:production) { create(:production, organization: org) }
  let(:setup) { ProductionTicketing.for(production) }
  let(:show) { create(:show, production: production, date_and_time: 5.days.from_now) }
  let(:listing) { TicketListing.create!(show: show, status: "on_sale") }

  it "is the standard look when nothing is set" do
    colors = described_class.for(profile, setup, listing)
    expect(colors).to be_standard
    expect(colors.to_h).to eq(described_class::DEFAULTS)
  end

  it "takes the date's, else the production's, else the box office's" do
    profile.update!(page_background_color: "#000000", page_text_color: "#F1F5F9")
    expect(described_class.for(profile, setup, listing).to_h).to include(background: "#000000", text: "#f1f5f9", button: "#ec4899")

    setup.update!(page_background_color: "#fef3c7", page_button_color: "#374151", page_heading_color: "#111827", page_text_color: "#334155")
    expect(described_class.for(profile, setup, listing).background).to eq("#fef3c7")

    listing.update!(page_background_color: "#172554", page_button_color: "#fde047", page_heading_color: "#ffffff", page_text_color: "#d1d5db")
    colors = described_class.for(profile, setup, listing)
    expect(colors.background).to eq("#172554")
    expect(colors.button_ink).to eq("#111827")
    expect(described_class.for(profile, setup).background).to eq("#fef3c7")
  end

  it "keeps only what differs from the standard on the box office, and refuses what isn't a color" do
    profile.update!(page_background_color: "#FFFFFF", page_button_color: "2563eb")
    expect(profile.reload.page_background_color).to be_nil
    expect(profile.page_button_color).to eq("#2563eb")

    expect(profile.update(page_heading_color: "red")).to be(false)
    expect(profile.errors.full_messages.first).to include("must be a color")
  end

  it "puts white words on a dark button and dark words on a light one" do
    expect(described_class.new(button: "#ec4899").button_ink).to eq("#ffffff")
    expect(described_class.new(button: "#fde047").button_ink).to eq("#111827")
  end

  it "darkens a light button color for links inside the white boxes" do
    expect(described_class.new(button: "#ec4899").accent).to eq("#ec4899")
    expect(described_class.new(button: "#f5c518").accent).to eq("#6e590b")
  end
end
