# frozen_string_literal: true

require "rails_helper"

# The app's Account screen (/my/account) and the web's notification page post
# to the same endpoint. A form only changes the toggles it shows, and the app's
# form comes back to the app's screen.
RSpec.describe "Email notification preferences", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user).tap { |p| user.update!(default_person: p) } }

  before { post handle_signin_path, params: { email_address: user.email_address, password: password } }

  it "shows only real toggles on /my/account, and saving there leaves the rest alone" do
    get my_account_path
    expect(response.body).to include("Group invitations")
    expect(response.body).not_to include("notifications[cast_notifications]", "notifications[show_reminders]")

    patch account_notifications_path, params: { return_to: my_account_path,
                                                notifications: { vacancy_invitations: "0", audition_invitations: "1", message_digest: "1" } }

    expect(response).to redirect_to(my_account_path)
    user.reload
    expect(user.notification_enabled?(:vacancy_invitations)).to be(false)
    expect(user.notification_enabled?(:audition_invitations)).to be(true)
    expect(user.notification_enabled?(:group_invitations)).to be(true)
  end

  it "turns a toggle off when its box is unchecked, and stays on the web page by default" do
    patch account_notifications_path, params: { notifications: { group_invitations: "0" } }

    expect(response).to redirect_to(account_notifications_path)
    expect(user.reload.notification_enabled?(:group_invitations)).to be(false)
  end

  it "never redirects anywhere but the two notification screens" do
    patch account_notifications_path, params: { return_to: "https://evil.example", notifications: { group_invitations: "1" } }
    expect(response).to redirect_to(account_notifications_path)
  end
end
