# frozen_string_literal: true

require "rails_helper"

RSpec.describe PushNotificationService do
  let(:user) { create(:user) }
  let(:production) { create(:production, name: "Spring Revue") }

  before { create(:device_token, user: user) }

  # [user_id, notification] of every push queued so far
  def pushed
    ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job] == PushDeliveryJob }.map { |job| job[:args] }
  end

  it "reads an automated notice as the production talking, saying the template's push text" do
    message = create(:message, :system, production: production, template_key: "call_time",
                               subject: "Call time moved", push_body: "Call is now 7pm, not 6")

    described_class.notify_new_message(user, message)

    user_id, notification = pushed.last
    expect(user_id).to eq(user.id)
    expect(notification).to include("title" => "Spring Revue", "body" => "Call is now 7pm, not 6")
    expect(notification).not_to have_key("subtitle")
    expect(notification["data"]).to include("type" => "new_message", "path" => "/my/messages/#{message.id}")
  end

  it "falls back to the subject, and to CocoScout, for a notice with no push text or production" do
    message = create(:message, :system, subject: "Your W-9 was received")

    described_class.notify_new_message(user, message)

    expect(pushed.last.last).to include("title" => "CocoScout", "body" => "Your W-9 was received")
  end

  it "reads a person's message as a text from them, under the production" do
    casey = create(:user)
    create(:person, user: casey, name: "Casey Lane")
    message = create(:message, sender: casey, production: production, visibility: :production,
                               body: "Running   ten late, start without me")

    described_class.notify_new_message(user, message)

    expect(pushed.last.last).to include("title" => "Casey Lane", "subtitle" => "Spring Revue",
                                        "body" => "Running ten late, start without me")
  end

  it "sends nothing to someone without the app" do
    message = create(:message, :system, subject: "Hello")

    expect { described_class.notify_new_message(create(:user), message) }.not_to have_enqueued_job(PushDeliveryJob)
  end
end
