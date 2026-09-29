# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrganizationStaffMember, "W-9 status", type: :model do
  let(:org) { create(:organization, :pro) }
  let(:person) { create(:person, user: create(:user)) }
  let(:member) { create(:organization_staff_member, organization: org, person: person) }

  it "moves from not requested → requested → received" do
    expect(member.w9_status).to eq(:not_requested)
    expect(member.needs_w9?).to be(true)

    member.update!(w9_requested_at: Time.current)
    expect(member.w9_status).to eq(:requested)

    create(:w9_submission, organization: org, person: person, organization_staff_member: member)
    member.reload
    expect(member.w9_status).to eq(:received)
    expect(member.needs_w9?).to be(false)
  end

  it "doesn't need one when exempt, inactive, or when the org has W-9s turned off" do
    member.update!(tax_form_exempt: true)
    expect(member.w9_status).to eq(:exempt)
    expect(member.needs_w9?).to be(false)

    member.update!(tax_form_exempt: false, archived_at: Time.current)
    expect(member.needs_w9?).to be(false)

    member.update!(archived_at: nil)
    org.create_tax_setting!(w9_required: false)
    member.reload
    expect(member.w9_status).to eq(:not_required)
    expect(member.needs_w9?).to be(false)
  end

  it "doesn't change onboarding status" do
    member.update!(acknowledged_at: Time.current)
    person.update!(stripe_account_id: "acct_x", payouts_enabled: true)
    expect(member.needs_w9?).to be(true)
    expect(member.onboarding_status).to eq(:onboarded)
  end

  it "lists the memberships still owing a W-9" do
    other_org = create(:organization, :pro)
    done = create(:organization_staff_member, organization: other_org, person: person)
    create(:w9_submission, organization: other_org, person: person, organization_staff_member: done)
    member

    expect(described_class.pending_w9s([ person.id ])).to eq([ member ])
  end
end
