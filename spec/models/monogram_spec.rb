# frozen_string_literal: true

require "rails_helper"

# Initials are a monogram of at most two letters, little words dropped, for
# productions, people and groups alike (Tim, 2026-10-17): five letters
# spilling out of a small poster box was the complaint.
RSpec.describe Monogram do
  it "takes the first letter of the first two words that carry the name" do
    expect(Production.new(name: "The Rocky Horror Picture Show").initials).to eq("RH")
    expect(Production.new(name: "Halloween o' Weens").initials).to eq("HW")
    expect(Production.new(name: "Bawdy Burlesque for Beginners").initials).to eq("BB")
    expect(Production.new(name: "A Night of 1000 Stevies").initials).to eq("N1")
    expect(Production.new(name: "Rock & Roll").initials).to eq("RR")
    expect(Production.new(name: "Hags").initials).to eq("H")
  end

  it "does the same for people and groups" do
    expect(Person.new(name: "Mary Jane Van Der Berg").initials).to eq("MJ")
    expect(Person.new(name: "clay smith").initials).to eq("CS")
    expect(Group.new(name: "The Comedy Troupe").initials).to eq("CT")
  end

  it "falls back to the name's own words when every word is a little one, and to nothing for no name" do
    expect(Production.new(name: "The The").initials).to eq("TT")
    expect(Production.new(name: "").initials).to eq("")
    expect(Production.new(name: nil).initials).to eq("")
  end
end
