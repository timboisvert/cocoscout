# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestPromotionService do
  let(:org) { create(:organization, :pro) }
  let(:production) { create(:production, organization: org) }
  let(:show) { create(:show, production: production) }
  let(:role) { create(:role, production: production) }
  let(:show_payout) { create(:show_payout, show: show) }
  let!(:assignment) { create(:show_person_role_assignment, show: show, role: role, assignable: nil, guest_name: "Guest Gigi") }
  let!(:line_item) { show_payout.line_items.create!(is_guest: true, guest_name: "Guest Gigi", amount: 100) }

  it "converts the guest assignment and line item into a real Person and posts an earning" do
    result = described_class.promote!(line_item: line_item, email: "gigi@example.com")

    person = result.person
    expect(person).to be_present
    expect(person.email).to eq("gigi@example.com")
    expect(org.people).to include(person)

    expect(assignment.reload.assignable).to eq(person)
    expect(assignment.guest_name).to be_nil

    expect(line_item.reload.payee).to eq(person)
    expect(line_item).not_to be_is_guest
    expect(org.payout_balance_cents_for(person)).to eq(10_000) # earned, awaiting payout
  end

  it "reuses an existing person with the same email" do
    existing = org.people.create!(name: "Gigi", email: "gigi@example.com")
    expect(described_class.promote!(line_item: line_item, email: "GIGI@example.com").person).to eq(existing)
  end

  it "errors without an email" do
    expect(described_class.promote!(line_item: line_item, email: "").error).to be_present
  end

  it "errors on a non-guest line item" do
    person = create(:person)
    li = show_payout.line_items.create!(payee: person, amount: 50, is_guest: false)
    expect(described_class.promote!(line_item: li, email: "x@example.com").error).to match(/isn't a guest/)
  end
end
