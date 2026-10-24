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

  it "sends the in-app copy as an automated notice from the production, never a person" do
    expect {
      described_class.invitation_email(invitation).deliver_now
    }.to change(Message, :count).by(1)

    message = Message.order(:id).last
    expect(message.sender).to be_nil
    expect(message.system_generated).to be(true)
    expect(message.automated?).to be(true)
    expect(message.sender_name).to eq(production.name)
    expect(message.root_message.repliable?).to be(true)
  end

  it "subscribes nobody but the invitee (no bystander gets the replies)" do
    described_class.invitation_email(invitation).deliver_now

    message = Message.order(:id).last
    expect(message.root_message.message_subscriptions.pluck(:user_id)).to eq([ invitee_user.id ])
  end
end
