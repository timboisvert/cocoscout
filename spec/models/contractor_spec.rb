# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contractor, type: :model do
  let(:organization) { create(:organization) }

  it "squishes the name so stray whitespace can't mint a duplicate" do
    contractor = organization.contractors.create!(name: "  Improvised  Animorphs ")
    expect(contractor.name).to eq("Improvised Animorphs")

    dupe = organization.contractors.build(name: "improvised animorphs  ")
    expect(dupe).not_to be_valid
    expect(dupe.errors[:name]).to be_present
  end

  it "normalizes email to stripped lowercase" do
    contractor = organization.contractors.create!(name: "Sound Co", email: " Sound@Example.COM ")
    expect(contractor.email).to eq("sound@example.com")
  end
end
