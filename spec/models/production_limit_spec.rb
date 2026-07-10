# frozen_string_literal: true

require "rails_helper"

RSpec.describe Production, "free-plan production limit validation", type: :model do
  let(:organization) { create(:organization) }

  it "blocks a second schedulable production on the Producer plan" do
    create(:production, organization: organization)
    second = build(:production, organization: organization)

    expect(second).not_to be_valid
    expect(second.errors[:base].join).to match(/one production/i)
  end

  it "allows a course even when at the production limit" do
    create(:production, organization: organization)
    course = build(:production, organization: organization, production_type: "course")
    expect(course).to be_valid
  end

  it "allows unlimited productions for a paid org" do
    organization.update!(comped_indefinitely: true)
    create(:production, organization: organization)
    expect(build(:production, organization: organization)).to be_valid
  end
end
