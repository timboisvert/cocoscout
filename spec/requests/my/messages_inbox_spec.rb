# frozen_string_literal: true

require "rails_helper"

RSpec.describe "My::Messages inbox", type: :request do
  let(:password) { "Password123!" }
  let(:viewer) { create(:user, password: password) }
  let!(:viewer_person) { create(:person, user: viewer).tap { |p| viewer.update!(default_person: p) } }

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  before { sign_in(viewer) }

  it "renders the density switcher when there are messages" do
    sender = create(:user)
    create(:person, name: "Pat Sender", user: sender)
    MessageService.create_message(
      sender: sender, recipients: [ viewer_person ],
      subject: "Hello", body: "Hi there", message_type: :direct, visibility: :personal
    )

    get my_messages_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Comfortable") # density switcher option
    expect(response.body).to include("msg-density-compact")
  end

  it "shows a system notification as 'Automated Notification', not its fallback sender" do
    admin = create(:user)
    create(:person, name: "Andy Wanacott", user: admin)

    MessageService.create_message(
      sender: admin, recipients: [ viewer_person ],
      subject: "Edit suggested for Femme Feedback", body: "An edit was suggested.",
      message_type: :direct, visibility: :personal, system_generated: true
    )

    get my_messages_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Automated Notification")
    expect(response.body).not_to include("Andy Wanacott")
  end
end
