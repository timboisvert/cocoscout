# frozen_string_literal: true

require "rails_helper"

# A fill-in invitation is an automated notice. Its in-app copy must never be
# "from" a person: it used to borrow whichever org member came back first, so
# a whole cast got "Replacement needed" messages from someone unrelated to the
# show, and their replies went to that person's inbox.
RSpec.describe VacancyInvitationMailer, type: :mailer do
  let(:role_vacancy) { create(:role_vacancy) }
  let(:production) { role_vacancy.show.production }
  let(:bystander_user) { create(:user) }
  let(:invitee_user) { create(:user) }
  let(:invitee) { create(:person, user: invitee_user) }
  let(:invitation) { create(:role_vacancy_invitation, role_vacancy: role_vacancy, person: invitee) }

  before do
    # An org member who has nothing to do with the production — the old
    # fallback would have picked them as the sender.
    create(:organization_role, organization: production.organization, user: bystander_user)
  end

  # On V1.1 the in-app copy is a Notification in the Casting group
  # (NotificationGroups), never a Message from a person.
  it "sends the in-app copy as an automated Casting notification, never a message from a person" do
    expect {
      described_class.invitation_email(invitation).deliver_now
    }.to change(Notification, :count).by(1).and change(Message, :count).by(0)

    notification = Notification.order(:id).last
    expect(notification.user).to eq(invitee_user)
    expect(notification.category).to eq("casting")
    expect(notification.kind).to eq("vacancy_invitation")
    expect(notification.body).to be_present
  end

  it "tells nobody but the invitee (no bystander gets a copy)" do
    described_class.invitation_email(invitation).deliver_now

    expect(Notification.where(user: bystander_user)).to be_empty
    expect(Notification.pluck(:user_id)).to eq([ invitee_user.id ])
  end
end
