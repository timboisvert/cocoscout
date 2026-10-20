# frozen_string_literal: true

require "rails_helper"

# V1.1 plan Phase 2: Pay People on a phone keeps its accordion, pins the
# running total and the one button to the bottom, and opens Hours and
# Tips as sheets with a stepper on the hours line.
RSpec.describe "Pay People on a phone", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner, stripe_customer_id: "cus_1", funding_payment_method_id: "pm_1", funding_payment_method_type: "us_bank_account") }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:person) { create(:person, name: "Ready Rae", stripe_account_id: "acct_r", payouts_enabled: true) }
  let!(:member) { create(:organization_staff_member, organization: org, person: person, hourly_rate_cents: 2000) }
  let(:app_ua) { "CocoScout/1.1 (12; nav 2) Turbo Native iOS" }

  before do
    create(:staff_time_entry, organization: org, person: person, approved_at: Time.current, approved_by: owner)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  def page(headers = {})
    get manage_staffing_pay_path, headers: headers
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body)
  end

  it "pins the total, the count and Add to payout run to the bottom below desktop width" do
    doc = page
    bar = doc.at_css("[data-pay-phone-bar]")
    expect(bar["class"]).to include("lg:hidden", "fixed", "bottom-0")
    expect(bar.at_css("[data-pay-run-target='grandTotal']").text).to eq("$0.00")
    expect(bar.at_css("[data-pay-run-target='count']")).to be_present
    expect(bar.at_css("button[type='submit']").text).to include("Add to payout run")
    # The desktop row of buttons stays for lg up only.
    expect(doc.css("button[type='submit']").size).to eq(2)
    expect(page("User-Agent" => app_ua).at_css("[data-pay-phone-bar]")["class"]).to include("pr-[96px]")
  end

  it "opens Hours, the pull, the tips sheet and the review steps as sheets on a phone" do
    doc = page
    sheets = doc.css("[data-pay-sheet]")
    expect(sheets.size).to eq(5) # one person's Hours, Pull in approved hours, Tips, missing-hours check, review
    sheets.each { |sheet| expect(sheet["class"]).to include("max-sm:rounded-b-none") }
    hours = doc.at_css("#pay-hours-modal-#{member.id}")
    expect(hours.at_css("[data-pay-sheet]")).to be_present
  end

  it "puts a half-hour stepper beside the additional-hours box" do
    row = page.at_css("#pay-hours-modal-#{member.id} [data-adhoc-row]")
    stepper = row.at_css("[data-controller='number-stepper']")
    expect(stepper["data-number-stepper-step-value"]).to eq("0.5")
    expect(stepper.css("button").map { |b| b["data-action"] }).to eq([ "number-stepper#down", "number-stepper#up" ])
    expect(stepper.at_css("input[data-adhoc-hours]")["data-number-stepper-target"]).to eq("input")
  end
end
