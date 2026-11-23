# frozen_string_literal: true

require "rails_helper"

# What happens when Apple or Google says who someone is (the sign-in plan's
# "After Apple or Google" and its safety rule; Tim, 2026-11-22).
RSpec.describe SignIn::Resolve do
  include ActiveJob::TestHelper

  def profile(email: "maya@example.com", uid: "g-1", provider: "google", verified: true, private_email: false)
    SignIn::Resolve::Profile.new(provider: provider, uid: uid, email: email, email_verified: verified, private_email: private_email,
                                 first_name: "Maya", last_name: "Lin", refresh_token: nil)
  end

  it "signs in a known Google account" do
    user = create(:user)
    user.user_identities.create!(provider: "google", uid: "g-1", email: user.email_address)
    result = described_class.call(profile(email: "someone-else@example.com"))
    expect([ result.kind, result.user ]).to eq([ :known, user ])
  end

  it "connects an account nobody chose a password for, replacing the password and saying so" do
    user = User.create_unclaimed!(email_address: "maya@example.com")
    digest = user.password_digest
    expect { described_class.call(profile) }.to change(Notification, :count).by(1)
    expect(user.reload.user_identities.sole.provider).to eq("google")
    expect(user.password_digest).not_to eq(digest)
    expect(user.email_verified_at).to be_present
    expect(enqueued_jobs.map { |job| job[:args][0..1] }).to include([ "AuthMailer", "method_connected" ])
  end

  it "asks an account with a chosen password, and every superadmin, to connect once" do
    chosen = create(:user, email_address: "maya@example.com", password: "Password123!")
    expect(described_class.call(profile).kind).to eq(:needs_proof)
    expect(chosen.user_identities).to be_empty

    admin = User.create_unclaimed!(email_address: User::SUPERADMIN_EMAILS.first)
    expect(described_class.call(profile(email: admin.email_address, uid: "g-2")).kind).to eq(:needs_proof)
  end

  it "needs a real address for Hide My Email or an unconfirmed one, and offers a new account for an unknown one" do
    expect(described_class.call(profile(provider: "apple", email: "x@privaterelay.appleid.com", private_email: true)).kind).to eq(:needs_email)
    expect(described_class.call(profile(verified: false)).kind).to eq(:needs_email)
    expect(described_class.call(profile(email: "new@example.com")).kind).to eq(:new_account)
  end

  it "won't connect a Google account already connected to someone else" do
    other = create(:user)
    other.user_identities.create!(provider: "google", uid: "g-1")
    user = create(:user)
    expect { SignIn::Connect.call(user: user, profile: profile, proof: :signed_in) }.to raise_error(SignIn::Connect::Taken)
  end
end
