# frozen_string_literal: true

require "rails_helper"

RSpec.describe "My::Messages archiving", type: :request do
  let(:password) { "Password123!" }
  let(:viewer) { create(:user, password: password) }
  let!(:viewer_person) { create(:person, user: viewer).tap { |p| viewer.update!(default_person: p) } }
  let(:sender) { create(:user) }
  let!(:thread) do
    MessageService.create_message(
      sender: sender, recipients: [ viewer_person ],
      subject: "ArchiveMe Thread", body: "hello",
      message_type: :direct, visibility: :personal
    )
  end

  before do
    create(:person, name: "Sandy Sender", user: sender)
    post handle_signin_path, params: { email_address: viewer.email_address, password: password }
  end

  it "removes an archived thread from the inbox and shows it under the Archived filter" do
    get my_messages_path
    expect(response.body).to include("ArchiveMe Thread")

    post archive_my_message_path(thread)
    expect(viewer.message_subscriptions.find_by(message: thread)).to be_archived

    get my_messages_path
    expect(response.body).not_to include("ArchiveMe Thread")

    get my_messages_path(filter: "archived")
    expect(response.body).to include("ArchiveMe Thread")
  end

  it "restores an unarchived thread to the inbox" do
    post archive_my_message_path(thread)
    post unarchive_my_message_path(thread)

    expect(viewer.message_subscriptions.find_by(message: thread)).not_to be_archived
    get my_messages_path
    expect(response.body).to include("ArchiveMe Thread")
  end

  it "doesn't count an archived thread toward unread" do
    sub = viewer.message_subscriptions.find_by(message: thread)
    sub.update!(unread_count: 1)
    expect(viewer.unread_message_count).to be >= 1

    post archive_my_message_path(thread)
    expect(viewer.reload.unread_message_count).to eq(0)
  end
end
