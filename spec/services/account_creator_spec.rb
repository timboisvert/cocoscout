# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccountCreator do
  it "creates an account with no chosen password, a confirmed address, and the name entered" do
    result = described_class.call(email: "New@Example.com", name: "  Maya   Okafor ", email_verified: true)

    expect(result.user).to be_persisted
    expect(result.user.email_address).to eq("new@example.com")
    expect(result.user.password_chosen?).to be(false)
    expect(result.user.email_verified_at).to be_present
    expect(result.person.name).to eq("Maya Okafor")
    expect(result.user.default_person).to eq(result.person)
  end

  it "still creates an account with a chosen password, named from the email" do
    result = described_class.call(email: "sam.lee@example.com", password: "Password123!")

    expect(result.user.password_chosen?).to be(true)
    expect(result.user.email_verified_at).to be_nil
    expect(result.person.name).to eq("Sam.Lee")
  end

  it "adopts the person an organization already added under that address" do
    added = create(:person, email: "added@example.com", name: "Added Person", user: nil)

    result = described_class.call(email: "added@example.com", email_verified: true)

    expect(result.person).to eq(added)
    expect(added.reload.user).to eq(result.user)
    expect(added.name).to eq("Added Person")
  end

  it "does not take a person who already belongs to someone else" do
    owner = create(:user, email_address: "moved-on@example.com")
    theirs = create(:person, email: "old@example.com", user: owner)

    result = described_class.call(email: "old@example.com", email_verified: true)

    expect(theirs.reload.user).to eq(owner)
    expect(result.person).not_to eq(theirs)
    expect(result.person.user).to eq(result.user)
  end

  it "returns the unsaved user when the email is no good" do
    result = described_class.call(email: "not-an-email")

    expect(result.user).not_to be_persisted
    expect(result.person).to be_nil
  end
end
