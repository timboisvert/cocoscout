# frozen_string_literal: true

require "rails_helper"

# What Mailgun saw happen to emails to followers: signed, handled once, and a
# bounce or complaint stops every organization from mailing that address.
RSpec.describe "Mailgun webhooks", type: :request do
  let(:key) { "whsec-test" }
  let(:org) { create(:organization, :pro) }
  let(:follower) { Follower.for!(org, "maria@example.com") }
  let(:email) { org.follower_emails.create!(subject: "Hi", status: "sent") }
  let!(:delivery) { email.follower_email_deliveries.create!(follower: follower, email: follower.email, status: "sent", mailgun_message_id: "abc@news.example") }

  before { allow(ENV).to receive(:[]).and_call_original; allow(ENV).to receive(:[]).with("MAILGUN_WEBHOOK_SIGNING_KEY").and_return(key) }

  def signed(event_data, signing_key: key)
    timestamp = Time.current.to_i.to_s
    token = SecureRandom.hex(16)
    { signature: { timestamp: timestamp, token: token, signature: OpenSSL::HMAC.hexdigest("SHA256", signing_key, "#{timestamp}#{token}") },
      "event-data": event_data }
  end

  it "turns away an unsigned or wrongly signed event" do
    post mailgun_webhook_path, params: signed({ id: "e1", event: "delivered" }, signing_key: "wrong"), as: :json
    expect(response).to have_http_status(:not_acceptable)
  end

  it "marks a delivery delivered, once" do
    payload = signed({ id: "e2", event: "delivered", recipient: "maria@example.com", "user-variables": { delivery_id: delivery.id.to_s } })
    post mailgun_webhook_path, params: payload, as: :json
    expect(delivery.reload.status).to eq("delivered")
    delivery.update!(status: "sent")
    post mailgun_webhook_path, params: payload, as: :json
    expect(delivery.reload.status).to eq("sent")
  end

  it "suppresses a permanent bounce everywhere, and finds the delivery by its message id" do
    post mailgun_webhook_path, params: signed({ id: "e3", event: "failed", severity: "permanent", recipient: "maria@example.com",
                                                message: { headers: { "message-id": "abc@news.example" } } }), as: :json
    expect(delivery.reload.status).to eq("bounced")
    expect(EmailSuppression.suppressed?("maria@example.com")).to be(true)
    expect(follower.reload.status).to eq("bounced")
    expect(Follower.emailable).not_to include(follower)
  end

  it "ignores a temporary failure and suppresses a complaint" do
    post mailgun_webhook_path, params: signed({ id: "e4", event: "failed", severity: "temporary", recipient: "maria@example.com" }), as: :json
    expect(EmailSuppression.count).to eq(0)
    post mailgun_webhook_path, params: signed({ id: "e5", event: "complained", recipient: "maria@example.com", "user-variables": { delivery_id: delivery.id.to_s } }), as: :json
    expect(EmailSuppression.find_by(email: "maria@example.com").reason).to eq("complained")
    expect(follower.reload.status).to eq("complained")
  end
end
