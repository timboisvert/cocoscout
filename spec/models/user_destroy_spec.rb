# frozen_string_literal: true

require "rails_helper"

# Superadmin's suspicious-people sweep (and any account deletion) ends in
# user.destroy!. Every table that points at users with a NOT NULL foreign key
# has to go with the user, or Postgres refuses the delete.
RSpec.describe User, "destroy" do
  let(:user) { create(:user) }
  let(:org) { create(:organization) }
  let(:production) { create(:production, organization: org) }

  it "takes its reactions, poll votes, wizard states and email batches with it" do
    message = create(:message)
    create(:message_reaction, message: message, user: user, emoji: "like")
    poll = MessagePoll.new(message: create(:message), question: "Which night?", max_votes: 1)
    poll.message_poll_options.build(text: "Friday", position: 0)
    poll.message_poll_options.build(text: "Saturday", position: 1)
    poll.save!
    MessagePollVote.create!(message_poll_option: poll.message_poll_options.first, user: user)
    AuditionWizardState.create!(user: user, production: production, state: {})
    EmailBatch.create!(user: user, subject: "Hello", recipient_count: 1)
    registration = create(:course_registration, user: user)

    expect { user.destroy! }.not_to raise_error
    expect(MessageReaction.where(user_id: user.id)).to be_empty
    expect(MessagePollVote.where(user_id: user.id)).to be_empty
    expect(AuditionWizardState.where(user_id: user.id)).to be_empty
    expect(EmailBatch.where(user_id: user.id)).to be_empty
    expect(registration.reload.user_id).to be_nil
  end
end
