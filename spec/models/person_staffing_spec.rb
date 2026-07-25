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

    it "drops :payment once a bank is connected" do
      person = create(:person, stripe_account_id: "acct_test123", payouts_enabled: true)
      expect(person.pool_profile_gaps).not_to include(:payment)
    end
  end
end
