# frozen_string_literal: true

require "rails_helper"

# Regression: per-form CSRF tokens (Rails 8 defaults) are minted for the form's
# action at render time. The "Mark paid another way" modal form is rendered with
# `url: "#"` and payment_actions_controller.js later points its action at the
# line item's mark_paid path, so its default per-form token would be minted for
# "#" and rejected with a 422 in production. The fix passes the session-wide
# token via `authenticity_token: form_authenticity_token`. The test env disables
# forgery protection, so this spec re-enables it and submits the token actually
# rendered in the form to the path the JS would set.
RSpec.describe "Manage::ShowPayouts mark-paid modal CSRF", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner, enabled_offline_payout_methods: [ "cash" ]) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }
  let!(:show) { create(:show, production: production, event_type: :show, date_and_time: 3.days.ago) }
  let!(:financials) { create(:show_financials, :complete, show: show, ticket_revenue: 500) }
  let!(:payout) { ShowPayout.create!(show: show, status: "awaiting_payout", calculated_at: Time.current, total_payout: 120) }
  let!(:line_item) do
    # No Stripe account — the payee that gets the offline "Mark paid another way" flow.
    ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person, name: "Offline Olive"), amount: 120)
  end

  before do
    # Sign in while forgery protection is still off (the default in test),
    # then turn it on so the submissions below are actually verified.
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    ActionController::Base.allow_forgery_protection = true
  end

  after { ActionController::Base.allow_forgery_protection = false }

  it "accepts the mark-paid form's rendered token at the JS-set line-item path" do
    get manage_money_show_payout_path(show)
    expect(response).to have_http_status(:ok)

    form = Nokogiri::HTML(response.body).at_css('form[data-payment-actions-target="markPaidForm"]')
    expect(form).to be_present
    token = form.at_css('input[name="authenticity_token"]')&.[]("value")
    expect(token).to be_present

    post manage_mark_line_item_paid_money_show_payout_path(show, line_item),
         params: { authenticity_token: token, payment_method: "cash" }

    expect(response.status).not_to eq(422)
    expect(line_item.reload.paid?).to be(true)
  end

  it "rejects a submission without a token (sanity check that protection is on)" do
    post manage_mark_line_item_paid_money_show_payout_path(show, line_item),
         params: { payment_method: "cash" }

    expect(response.status).to eq(422)
    expect(line_item.reload.paid?).to be(false)
  end
end
