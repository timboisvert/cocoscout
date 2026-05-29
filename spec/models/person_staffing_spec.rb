# frozen_string_literal: true

require "rails_helper"

RSpec.describe Person, type: :model do
  describe "#in_any_talent_pool?" do
    it "is false when the person is in no talent pools" do
      expect(create(:person).in_any_talent_pool?).to be(false)
    end

    it "is true when the person belongs to a talent pool" do
      person = create(:person)
      pool = create(:talent_pool)
      create(:talent_pool_membership, talent_pool: pool, member: person)
      expect(person.in_any_talent_pool?).to be(true)
    end
  end

  describe "#pool_profile_gaps" do
    it "reports all three gaps for a bare profile" do
      person = create(:person, phone: nil)
      expect(person.pool_profile_gaps).to contain_exactly(:contact, :headshot, :payment)
    end

    it "drops :contact once a phone is present" do
      person = create(:person, phone: "5551234567")
      expect(person.pool_profile_gaps).not_to include(:contact)
    end

    it "drops :headshot once a headshot exists" do
      person = create(:person)
      create(:profile_headshot, profileable: person)
      expect(person.reload.pool_profile_gaps).not_to include(:headshot)
    end

    it "drops :payment once a payment method is configured" do
      person = create(:person, zelle_identifier: "a@b.com", zelle_identifier_type: "EMAIL")
      expect(person.pool_profile_gaps).not_to include(:payment)
    end
  end

  describe "#preferred_payment_info (Zelle preferred)" do
    it "prefers Zelle when both are configured and no explicit preference is set" do
      person = create(:person,
                      zelle_identifier: "z@b.com", zelle_identifier_type: "EMAIL",
                      venmo_identifier: "veebartender", venmo_identifier_type: "USER_HANDLE")
      expect(person.preferred_payment_info[:method]).to eq("zelle")
    end

    it "honors an explicit Venmo preference" do
      person = create(:person,
                      preferred_payment_method: "venmo",
                      zelle_identifier: "z@b.com", zelle_identifier_type: "EMAIL",
                      venmo_identifier: "veebartender", venmo_identifier_type: "USER_HANDLE")
      expect(person.preferred_payment_info[:method]).to eq("venmo")
    end

    it "falls back to Venmo when only Venmo is configured" do
      person = create(:person, venmo_identifier: "veebartender", venmo_identifier_type: "USER_HANDLE")
      expect(person.preferred_payment_info[:method]).to eq("venmo")
    end

    it "is nil when nothing is configured" do
      expect(create(:person).preferred_payment_info).to be_nil
    end
  end
end
