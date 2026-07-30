# frozen_string_literal: true

require "rails_helper"

RSpec.describe StaffOnboardingInviter do
  let(:owner) { create(:user) }
  let(:org) { create(:organization, :pro, owner: owner) }
  let(:person) { create(:person, name: "Pat Payee", email: "pat@example.com") }
  let(:member) { create(:organization_staff_member, organization: org, person: person, onboarding_state: "added") }

  it "sends the onboarding email, an in-app message, and marks the member invited" do
    # A claimed account (has logged in) gets the onboarding email; an unclaimed
    # one gets the set-password invite instead (covered separately below).
    person.update!(user: create(:user, last_seen_at: Time.current))
    expect(StaffOnboardingMailer).to receive(:invite).with(member, hash_including(:subject, :body)).and_return(double(deliver_later: true))
    expect(MessageService).to receive(:send_direct).with(hash_including(recipient_person: person, sender: owner, organization: org)).and_return(true)

    described_class.call(staff_member: member, sender: owner)

    expect(member.reload.onboarding_state).to eq("invited")
  end

  it "creates account access for a person with no login yet" do
    person.update!(user: nil)
    allow(StaffOnboardingMailer).to receive(:invite).and_return(double(deliver_later: true))
    allow(MessageService).to receive(:send_direct)

    described_class.call(staff_member: member, sender: owner)

    expect(person.reload.user).to be_present
    expect(PersonInvitation.pending.where(email: "pat@example.com", organization: org)).to exist
  end

  it "renders the invite copy from the content template, linking to the welcome page" do
    preview = described_class.preview(staff_member: member)
    expect(preview[:body]).to include("/my/onboarding/#{org.id}")
    expect(preview[:body]).not_to include("/payments/setup")
  end

  it "raises when there's no email to reach the worker" do
    person.update_columns(email: nil)
    member.update_columns(personal_email: nil)

    expect { described_class.call(staff_member: member, sender: owner) }
      .to raise_error(StaffOnboardingInviter::Error, /no email/i)
  end
end
