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

  # The Gmail-style single line squeezed the subject into ~100px on a phone.
  # The row now stacks: who + when on one line, subject underneath.
  describe "the inbox row on mobile" do
    before do
      sender = create(:user)
      create(:person, name: "Pat Sender", user: sender)
      MessageService.create_message(
        sender: sender, recipients: [ viewer_person ],
        subject: "A subject long enough to need the whole width", body: "And a snippet after it",
        message_type: :direct, visibility: :personal
      )
    end

    it "stacks the row on phones and lays it out in one line from sm up" do
      get my_messages_path

      expect(response.body).to include("msg-row flex flex-col sm:flex-row")
      expect(response.body).not_to include("msg-participants flex-shrink-0 w-40")
    end

    it "keeps a date visible in both layouts" do
      get my_messages_path

      expect(response.body).to include("msg-date hidden sm:block")
    end

    it "never asks an element to hide while setting a display that overrides it" do
      get my_messages_path

      # `hidden` (display:none) loses to any display utility sorting after it in
      # the built Tailwind CSS, so an element carrying both stays visible.
      overrides_hidden = %w[inline inline-block inline-flex table]
      conflicted = response.body.scan(/class="([^"]*)"/).flatten.select do |classes|
        names = classes.split(/\s+/)
        names.include?("hidden") && names.any? { |n| overrides_hidden.include?(n) }
      end

      expect(conflicted).to be_empty,
        "these elements ask to hide but set a display that overrides it: #{conflicted.inspect}"
    end
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
