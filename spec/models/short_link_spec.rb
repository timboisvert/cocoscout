# frozen_string_literal: true

require "rails_helper"

RSpec.describe ShortLink do
  let(:org) { create(:organization) }
  let(:production) { create(:production, organization: org) }

  it "issues one canonical code per target and never a second" do
    a = described_class.canonical_for!(production)
    b = described_class.canonical_for!(production)
    expect(a).to eq(b)
    expect { described_class.create!(target: production, kind: "canonical", organization: org) }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "upcases codes and needs a label on a named link" do
    link = described_class.new(target: production, organization: org, kind: "named", code: "ab12c")
    expect(link).not_to be_valid
    link.label = "Poster"
    expect(link).to be_valid
    expect(link.code).to eq("AB12C")
  end

  it "takes a new code until somebody follows it" do
    link = described_class.canonical_for!(production)
    first = link.code
    expect(link).to be_unused
    expect(link.regenerate_code!).to be(true)
    expect(link.reload.code).not_to eq(first)
    expect(described_class.lookup(first)).to be_nil

    link.record_click!
    kept = link.code
    expect(link.regenerate_code!).to be(false)
    expect(link.reload.code).to eq(kept)
    expect(link).not_to be_unused
  end

  it "resolves its destination when followed, with a preset code and a date" do
    TicketingProfile.for(org).update!(slug: "sgtix")
    link = described_class.create!(target: production, organization: org, kind: "named", label: "Friends", query: { "code" => "FRIENDS" })
    expect(link.destination_path).to eq("/tickets/sgtix/#{production.public_key}?code=FRIENDS")
    expect(link.destination_path("oct-17")).to eq("/tickets/sgtix/#{production.public_key}?code=FRIENDS&date=oct-17")
    expect(link.short_path("oct-17")).to eq("/t/#{link.code}/oct-17")
  end
end
