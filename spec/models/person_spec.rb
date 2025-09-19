require 'rails_helper'

describe Person, type: :model do
  it "is valid with valid attributes" do
    expect(build(:person)).to be_valid
  end

  it "is invalid without an email" do
    person = build(:person, email: nil)
    expect(person).not_to be_valid
  end

  it "is invalid without a stage_name" do
    person = build(:person, stage_name: nil)
    expect(person).not_to be_valid
  end
end
