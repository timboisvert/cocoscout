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

  it "leaves notices a manager writes as messages" do
    expect { send_automated("cast_notification") }.to change(Message, :count).by(1).and(not_change(Notification, :count))
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
