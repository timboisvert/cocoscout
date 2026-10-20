# frozen_string_literal: true

require "rails_helper"

# The worksheet as a page (V1.1 plan §6): its edit template was missing, so
# the payout page's "enter financial data first" and a failed save raised.
RSpec.describe "The financials worksheet page", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, owner: owner) }
  let(:production) { create(:production, organization: org) }
  let!(:show) { create(:show, production: production, date_and_time: 2.days.ago.change(hour: 19)) }

  before do
    create(:organization_role, :manager, user: owner, organization: org)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "renders, with Save pinned and Cancel back to the financials" do
    get manage_edit_money_show_financials_path(show)
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    worksheet = doc.at_css("#financialWorksheet")
    expect(worksheet["class"]).not_to include("hidden")
    expect(doc.css("a").map { |a| a["href"] }).to include(manage_money_show_financials_path(show))
    expect(response.body).to include("image/jpeg,image/png,application/pdf")
  end

  it "is where calculating a payout sends someone with no financials yet, and it opens" do
    post manage_calculate_money_show_payout_path(show)
    expect(response).to redirect_to(manage_edit_money_show_financials_path(show))
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Please enter financial data before calculating payouts.")
  end

  it "pins the payout's next step to the bottom of a phone: here, enter financials" do
    get manage_money_show_payout_path(show)
    expect(response).to have_http_status(:ok)
    bar = Nokogiri::HTML(response.body).at_css("[data-payout-phone-bar]")
    expect(bar.text).to include("Needs financials", "Enter financials")
    expect(bar.at_css("a")["href"]).to start_with(manage_edit_money_show_financials_path(show))
  end
end
