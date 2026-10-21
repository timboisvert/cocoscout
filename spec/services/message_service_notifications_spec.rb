# frozen_string_literal: true

require "rails_helper"

# V1.1 plan §9: automated notices from the areas that moved become
# Notifications in MessageService.create_message; people talking stay
# messages, as do notices a manager writes or edits before sending.
RSpec.describe "Automated notices become Notifications" do
  include ActiveJob::TestHelper

  let(:org) { create(:organization) }
  let(:person) { create(:person, name: "Sam Staffer", user: create(:user)) }

  def send_automated(template_key, subject: "Can you cover Friday?", body: %(<p>Open spot. <a href="https://cocoscout.com/my/vacancies/7">See it</a></p>), skip_digest: false)
    MessageService.send_direct(sender: nil, recipient_person: person, subject: subject, body: body, organization: org,
                               template_key: template_key, push_body: nil, system_generated: true, skip_digest: skip_digest)
  end

  it "turns a moved area's notice into a Notification with the body, its first link, and a digest owed" do
    result = nil
    expect { result = send_automated("vacancy_created") }.to change(Notification, :count).by(1).and(not_change(Message, :count))
    expect(result).to be_a(Notification)
    expect(result).to have_attributes(category: "casting", kind: "vacancy_created", title: "Can you cover Friday?",
                                      path: "/my/vacancies/7", organization: org, digest: true)
    expect(result.body).to include("Open spot.")
  end

  it "owes no digest for a notice that was never in the digest" do
    expect(send_automated("request_agreement_signature", skip_digest: true).digest).to be(false)
  end

  describe "a notice a manager can write (option 3)" do
    let(:manager) { create(:user) }

    def send_voiced(custom_words)
      MessageService.send_direct(sender: manager, recipient_person: person, subject: "You're cast in Sketch Night", body: "<p>Call is 6:30.</p>",
                                 organization: org, template_key: "cast_notification", system_generated: true, custom_words: custom_words)
    end

    it "is a Notification alone when the words are the template's, and it pushes and digests" do
      person.user.device_tokens.create!(token: "tok", platform: "ios")
      result = nil
      expect { result = send_voiced(false) }.to change(Notification, :count).by(1).and(not_change(Message, :count)).and(have_enqueued_job(PushDeliveryJob))
      expect(result).to be_a(Notification)
      expect(result.digest).to be(true)
    end

    it "is a Notification and a Message from the manager when they changed the words: one push, the message's" do
      result = nil
      expect { result = send_voiced(true) }.to change(Notification, :count).by(1).and(change(Message, :count).by(1))
      expect(result).to be_a(Message)
      expect(result.sender).to eq(manager)
      expect(result).not_to be_automated
      notification = person.user.notifications.last
      expect(notification.message).to eq(result)
      expect(notification.digest).to be(false)
      # Reply on the notification opens the manager's thread (V1.1 plan §9).
      expect(notification.reply_path).to eq("/my/messages/#{result.id}")
    end

    it "reads the notification when the manager's message is read" do
      message = send_voiced(true)
      message.message_subscriptions.find_by(user: person.user).mark_read!
      expect(person.user.notifications.last).to be_read
    end
  end

  it "leaves people talking as messages" do
    sender = create(:user)
    expect {
      MessageService.send_direct(sender: sender, recipient_person: person, subject: "Hi", body: "Hello", organization: org)
    }.to change(Message, :count).by(1).and(not_change(Notification, :count))
  end

  describe "the unread digest" do
    it "emails an owed notification once, linking to it" do
      # The test seed's digest template is a stub; the real one carries the list.
      ContentTemplate.find_by(key: "unread_digest").update!(body: "<p>Hi</p>{{thread_list}}")
      notification = send_automated("vacancy_created")
      notification.update_column(:created_at, 2.hours.ago)
      ActionMailer::Base.deliveries.clear

      perform_enqueued_jobs { UnreadDigestJob.perform_now }
      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([ person.user.email_address ])
      expect(mail.html_part.body.to_s).to include("Can you cover Friday?", "/notifications/#{notification.id}/open")
      expect(notification.reload.digested_at).to be_present
    end

    it "skips someone who switched that group's email off" do
      person.user.set_notification_switches(email: { "casting" => "0" })
      person.user.save!
      expect(send_automated("vacancy_created").digest).to be(false)
    end
  end
end
