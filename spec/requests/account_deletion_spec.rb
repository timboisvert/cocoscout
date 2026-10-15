# frozen_string_literal: true

require "rails_helper"

# Delete my account, from Account Settings on the website or in the app
# (Apple requires the app to offer it): a request the superadmins finish
# within 30 days, which the person can take back until then.
RSpec.describe "Deleting my account", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password, email_address: "ida@example.com") }
  let!(:person) { create(:person, user: user, name: "Ida Performer").tap { |p| user.update!(default_person: p) } }
  let(:in_app) { { "User-Agent" => "CocoScout (iPhone) Hotwire Native iOS; Turbo Native iOS;" } }

  before do
    post handle_signin_path, params: { email_address: user.email_address, password: password }
    ActionMailer::Base.deliveries.clear
  end

  it "takes the request in the app, emails the superadmins once, and can be taken back" do
    get account_path, headers: in_app
    expect(response.body).to include("Delete my account", "Delete your account?")
    expect(response.body).not_to include("mailto:support@cocoscout.com?subject=Delete")

    perform_enqueued_jobs do
      post request_deletion_account_path, headers: in_app
      post request_deletion_account_path, headers: in_app
    end
    expect(response).to redirect_to(account_path)
    expect(user.reload.deletion_requested_at).to be_present

    mails = ActionMailer::Base.deliveries
    expect(mails.flat_map(&:to)).to match_array(User::SUPERADMIN_EMAILS)
    expect(mails.first.subject).to eq("Ida Performer asked to delete their CocoScout account")
    expect(mails.first.html_part.decoded).to include("ida@example.com", "the iPhone app", "/superadmin/people/#{person.id}")

    get account_path, headers: in_app
    expect(response.body).to include("Deleting your account", "Keep my account")

    delete cancel_deletion_account_path
    expect(user.reload.deletion_requested_at).to be_nil
  end

  it "says it came from the Android app when it did" do
    android = { "User-Agent" => "Mozilla/5.0 (Linux; Android 16; Pixel 8) AppleWebKit/537.36 Chrome/141.0 Mobile Safari/537.36 Hotwire Native Android; Turbo Native Android; bridge-components: [form menu]" }
    perform_enqueued_jobs { post request_deletion_account_path, headers: android }

    expect(ActionMailer::Base.deliveries.first.html_part.decoded).to include("the Android app")
  end

  it "shows superadmins who asked, on their page" do
    user.update!(deletion_requested_at: Time.zone.local(2026, 10, 12, 15))
    admin = create(:user, password: password, email_address: User::SUPERADMIN_EMAILS.first)
    create(:person, user: admin).tap { |p| admin.update!(default_person: p) }
    post handle_signin_path, params: { email_address: admin.email_address, password: password }

    get person_detail_path(person)
    expect(response.body).to include("Asked to be deleted", "Since October 12, 2026", "by November 11")
  end
end
