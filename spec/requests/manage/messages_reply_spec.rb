# frozen_string_literal: true

require "rails_helper"

# Replying to a system/automated message (nil sender, e.g. a contract-signed
# notification) from the manage side used to crash resolving the missing sender,
# and even once guarded it silently created nothing while saying "Reply sent".
# The manage reply now mirrors the member side: it routes such a reply to the
# production team as a new thread.
RSpec.describe "Manage::Messages#reply to a system message", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:owner_person) { create(:person, user: owner).tap { |p| owner.update!(default_person: p) } }
  let!(:org) { create(:organization, owner: owner) }
  let!(:org_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }

  let!(:system_message) do
    Message.create!(
      sender: nil,
      subject: "Contract signed",
      body: "A contract was signed.",
      message_type: "system",
      system_generated: true,
      visibility: "production",
      production: production,
      organization: org
    ).tap { |m| m.subscribe!(owner) }
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "doesn't crash and routes the reply to the production team as a new thread" do
    expect {
      post reply_manage_message_path(system_message), params: { body: "Thanks for the heads up" }
    }.to change(Message, :count).by_at_least(1)

    expect(response).to have_http_status(:redirect)
    follow_redirect!
    expect(response.body).to include("production team")

    reply = Message.where(message_type: "system").where.not(id: system_message.id).order(:created_at).last ||
            Message.where.not(id: system_message.id).order(:created_at).last
    expect(reply.body.to_plain_text).to eq("Thanks for the heads up")
    expect(reply.parent_message_id).to be_nil # a new root thread, not nested under the system message
  end
end
