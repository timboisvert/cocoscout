# frozen_string_literal: true

require "rails_helper"

RSpec.describe ShiftVacancyInvitationMailer, type: :mailer do
  let(:org) { create(:organization, owner: create(:user), name: "Stars & Garters") }
  let(:shift) { create(:shift, organization: org, house_role: create(:house_role, organization: org, name: "Bar"), starts_at: 1.week.from_now.change(hour: 19), ends_at: 1.week.from_now.change(hour: 23)) }
  let(:dana) { create(:person, name: "Dana Morris") }
  let(:priya) { create(:person, name: "Priya Kaur", email: "priya@example.com", user: create(:user)) }
  let!(:assignment) { shift.shift_assignments.create!(person: dana, position: 1).tap { |a| a.decline! } }
  let(:vacancy) { assignment.active_vacancy }

  it "sends the manager's stored words with this person's claim link, and a Notification in the Shifts group" do
    invitation = vacancy.invitations.create!(person: priya, email_subject: "Cover Bar?",
                                             email_body: "<p>Hi {{recipient_name}}, can you? <a href=\"{{claim_url}}\">Claim</a></p>")
    mail = described_class.invitation_email(invitation)
    expect(mail.to).to eq([ "priya@example.com" ])
    expect(mail.subject).to eq("Cover Bar?")
    html = (mail.html_part || mail).body.decoded
    expect(html).to include("Hi Priya, can you?", "/claim-shift/#{invitation.token}")

    expect(Message.count).to eq(0)
    notification = Notification.last
    expect(notification).to be_present
    expect(notification.user).to eq(priya.user)
    expect(notification.category).to eq("shifts")
    expect(notification.body).to include("/claim-shift/#{invitation.token}")
  end

  it "falls back to the template when no words were stored" do
    invitation = vacancy.invitations.create!(person: priya)
    mail = described_class.invitation_email(invitation)
    expect(mail.subject).to include("Can you cover a Bar shift")
    expect((mail.html_part || mail).body.decoded).to include("Stars &amp; Garters", "Claim this shift")
  end
end
