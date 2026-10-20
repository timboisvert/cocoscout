# frozen_string_literal: true

require "rails_helper"

RSpec.describe ManagerWords do
  it "ignores markup, spacing and entities" do
    expect(described_class.changed?([ "<div>Hi {{first_name}},</div><div>See you</div>", "<p>Hi {{first_name}},</p>\n<p>See you</p>" ])).to be(false)
    expect(described_class.changed?([ "Tom &amp; Jerry", "Tom & Jerry" ])).to be(false)
  end

  it "sees a real edit, and treats an empty draft as untouched" do
    expect(described_class.changed?([ "Hi there, bring a snack", "Hi there" ])).to be(true)
    expect(described_class.changed?([ nil, "Hi" ], [ "", "Body" ])).to be(false)
  end

  it "knows a note when there is one" do
    expect(described_class.note?(" ")).to be(false)
    expect(described_class.note?("Welcome aboard!")).to be(true)
  end
end
