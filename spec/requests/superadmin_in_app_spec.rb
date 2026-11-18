# frozen_string_literal: true

require "rails_helper"

# Superadmin in the app (Tim, 2026-11-14): its notifications open its pages,
# so generation-2 builds keep those pages in the app and the Coco menu
# reaches them, for a superadmin only.
RSpec.describe "Superadmin in the app", type: :request do
  let(:v1_1) { "CocoScout/1.1 (12; nav 2) Mozilla/5.0 (iPhone) AppleWebKit Hotwire Native iOS; Turbo Native iOS; bridge-components: [form menu]" }
  let(:superadmin) { create(:user, email_address: User::SUPERADMIN_EMAILS.first) }
  let(:owner) { create(:user) }

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: "Password123!" }
  end

  def nav
    bridge = Nokogiri::HTML(response.body).at_css('[data-controller="bridge--menu"]')
    JSON.parse(bridge["data-bridge--menu-nav-value"])
  end

  def items(nav) = nav["sections"].flat_map { |s| s["items"] }

  it "opens a new organization's notification on its Superadmin page" do
    superadmin
    org = Organization.create!(name: "The Holly Problem", owner: owner)
    notice = superadmin.notifications.find_by!(kind: "organization_created")

    sign_in(superadmin)
    get open_notification_path(notice)
    expect(response).to redirect_to(organization_detail_path(org))
    expect(notice.reload).to be_read
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("The Holly Problem")
  end

  it "opens a Pro upgrade's notification on the organization's finances page, in the app" do
    superadmin
    allow(StaffMeterService).to receive(:ensure_staffing_subscription!)
    org = Organization.create!(name: "The Holly Problem", owner: owner)
    org.start_pro_on_monthly_bill!
    notice = superadmin.notifications.find_by!(kind: "pro_started")

    sign_in(superadmin)
    get open_notification_path(notice), headers: { "User-Agent" => v1_1 }
    expect(response).to redirect_to(finances_org_detail_path(org_id: org.id))
    follow_redirect!(headers: { "User-Agent" => v1_1 })
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("The Holly Problem")
  end

  it "keeps Superadmin's pages in generation-2 builds instead of sending them to the browser" do
    rules = JSON.parse(Rails.public_path.join("hotwire-native/nav-2/path-configuration.json").read)["rules"]
    safari = rules.select { |rule| rule["properties"]["open_in"] == "safari" }.flat_map { |rule| rule["patterns"] }

    %w[/superadmin /superadmin/finances/orgs/12 /superadmin/organizations/12].each do |path|
      expect(safari.any? { |pattern| Regexp.new(pattern).match?(path) }).to be(false), path
    end
    expect(safari.any? { |pattern| Regexp.new(pattern).match?("/pricing") }).to be(true)

    # Its downloads open in the document viewer, not as a page of raw bytes.
    documents = rules.select { |rule| rule["properties"]["open_in"] == "document" }.flat_map { |rule| rule["patterns"] }
    %w[/superadmin/finances/statements/5 /superadmin/finances/invoices/5 /superadmin/finances/costs/export /superadmin/finances.csv].each do |path|
      expect(documents.any? { |pattern| Regexp.new(pattern).match?(path) }).to be(true), path
    end
    expect(documents.any? { |pattern| Regexp.new(pattern).match?("/superadmin/finances/orgs/12") }).to be(false)
  end

  it "gives a superadmin a Superadmin tile in the menu, and its whole nav on its pages" do
    sign_in(superadmin)

    get my_dashboard_path, headers: { "User-Agent" => v1_1 }
    tile = items(nav).find { |i| i["id"] == "superadmin" }
    expect(tile).to include("title" => "Superadmin", "path" => superadmin_path)

    get superadmin_path, headers: { "User-Agent" => v1_1 }
    expect(response).to have_http_status(:ok)
    titles = items(nav).map { |i| i["title"] }
    expect(titles).to include("Home", "Overview", "Organizations", "Finances", "Queue")
    ids = items(nav).map { |i| i["id"] }
    expect(ids).to all(be_present)
    expect(ids).to eq(ids.uniq)
  end

  it "gives nobody else a way in" do
    sign_in(owner)
    get my_dashboard_path, headers: { "User-Agent" => v1_1 }

    expect(items(nav).map { |i| i["path"] }.grep(%r{\A/superadmin})).to be_empty
    expect(nav["sections"].map { |s| s["label"] }).not_to include("Superadmin")
  end

  it "shows a superadmin the push switch for these notifications, and nobody else" do
    sign_in(superadmin)
    get account_notifications_path
    expect(response.body).to include("New organizations and Pro", 'name="push[platform]"')

    get signout_path
    sign_in(owner)
    get account_notifications_path
    expect(response.body).not_to include("New organizations and Pro")
  end
end
