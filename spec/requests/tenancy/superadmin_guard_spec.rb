# frozen_string_literal: true

require "rails_helper"

# The superadmin guard used to be an `only:` allowlist that had drifted 20+
# actions behind the controller — email_logs, bulk_destroy_people, cache_clear
# and friends were reachable by ANY signed-in user. The guard is unconditional
# now; these specs pin that.
RSpec.describe "Superadmin guard", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }

  before { post handle_signin_path, params: { email_address: user.email_address, password: password } }

  it "blocks email logs (bodies carry invite tokens and signing links)" do
    log = create(:email_log)

    get email_logs_path
    expect(response).to redirect_to(my_dashboard_path)

    get email_log_path(log)
    expect(response).to redirect_to(my_dashboard_path)
  end

  it "blocks bulk person destruction" do
    victim = create(:person)

    expect {
      delete bulk_destroy_people_path, params: { person_ids: victim.id.to_s }
    }.not_to change(Person, :count)
    expect(response).to redirect_to(my_dashboard_path)
  end

  it "blocks cache clearing" do
    post cache_clear_path
    expect(response).to redirect_to(my_dashboard_path)
  end

  it "blocks the queue retry sweep" do
    post queue_retry_all_failed_path
    expect(response).to redirect_to(my_dashboard_path)
  end

  it "blocks the new cash-adjustment action" do
    org = create(:organization)

    expect {
      post finances_cash_adjustment_path(org_id: org.id), params: { amount: "100" }
    }.not_to change(OrgCashEntry, :count)
    expect(response).to redirect_to(my_dashboard_path)
  end

  it "still allows a real superadmin through" do
    admin = create(:user, email_address: "boisvert@gmail.com", password: password)
    post handle_signin_path, params: { email_address: admin.email_address, password: password }

    get email_logs_path
    expect(response).to have_http_status(:ok)
  end
end
