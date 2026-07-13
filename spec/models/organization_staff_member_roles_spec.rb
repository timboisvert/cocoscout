# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrganizationStaffMember, "per-role rates", type: :model do
  let(:org) { create(:organization, :pro) }
  let(:person) { create(:person) }
  let(:member) { create(:organization_staff_member, organization: org, person: person, hourly_rate_cents: 1300) }
  let!(:bartender) { create(:house_role, organization: org, name: "Bartender") }
  let!(:barback) { create(:house_role, organization: org, name: "Barback") }

  it "stores a rate per role and syncs adds/removes" do
    member.sync_role_qualifications!(role_ids: [ bartender.id, barback.id ],
                                     rates: { bartender.id => "15", barback.id => "18.50" })

    expect(member.house_role_ids).to match_array([ bartender.id, barback.id ])
    expect(member.rate_cents_for(bartender)).to eq(1500)
    expect(member.rate_cents_for(barback)).to eq(1850)

    # Dropping barback removes its qualification.
    member.sync_role_qualifications!(role_ids: [ bartender.id ], rates: { bartender.id => "16" })
    expect(member.reload.house_role_ids).to eq([ bartender.id ])
    expect(member.rate_cents_for(bartender)).to eq(1600)
  end

  it "falls back to the member's default rate when a role rate is blank" do
    member.sync_role_qualifications!(role_ids: [ bartender.id ], rates: { bartender.id => "" })
    expect(member.rate_cents_for(bartender)).to eq(1300) # default
  end
end
