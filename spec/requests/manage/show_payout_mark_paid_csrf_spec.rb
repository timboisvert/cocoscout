# frozen_string_literal: true

require "rails_helper"

# The "Mark paid another way" modal form is rendered with url: "#" and its
# action is pointed at the right line item by JS at click time
# (payment_actions_controller#showMarkPaidModal). With Rails' per-form CSRF
# tokens, a token minted for action "#" is invalid at the real line-item path,
# so production rejected the POST with a 422 (InvalidAuthenticityToken). The
# form must carry the global session token instead.
#
# Forgery protection is off in the test env by default — which is why no other
# spec ever caught this — so this spec switches it on for the requests under test.
RSpec.describe "Mark paid another way CSRF", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }
  let!(:show) { create(:show, production: production, event_type: :show, date_and_time: 3.days.ago) }
  let!(:financials) { create(:show_financials, :complete, show: show, ticket_revenue: 500) }
  let!(:payout) { ShowPayout.create!(show: show, status: "awaiting_payout", calculated_at: Time.current, total_payout: 120) }
  let!(:li_unpaid) { ShowPayoutLineItem.create!(show_payout: payout, payee: create(:person, name: "Owed Ollie"), amount: 120) }

  before do
    org.update!(enabled_offline_payout_methods: [ "cash" ])
    # Sign in while protection is still off (the helper posts without a token),
    # then protect everything under test like production does.
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    @prev_forgery = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
  end

  after { ActionController::Base.allow_forgery_protection = @prev_forgery }

  it "accepts the modal's embedded token when posted to the JS-set line-item path" do
    get manage_money_show_payout_path(show)
    expect(response).to have_http_status(:ok)

    form = Nokogiri::HTML(response.body).at_css('form[data-payment-actions-target="markPaidForm"]')
    expect(form).to be_present
    token = form.at_css('input[name="authenticity_token"]')&.[]("value")
    expect(token).to be_present

    post manage_mark_line_item_paid_money_show_payout_path(show, li_unpaid),
         params: { authenticity_token: token, payment_method: "cash", paid_date: Date.current.to_s }

    expect(response).to have_http_status(:redirect)
    expect(li_unpaid.reload.manually_paid).to be(true)
  end

  it "rejects a submission without a token (sanity check that protection is on)" do
    post manage_mark_line_item_paid_money_show_payout_path(show, li_unpaid),
         params: { payment_method: "cash" }

    expect(response.status).to eq(422)
    expect(li_unpaid.reload.manually_paid).to be(false)
  end
end
