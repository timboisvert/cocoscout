# frozen_string_literal: true

require "rails_helper"

# The ticketing show page on a phone (V1.1 plan §4): status, a ⋯ menu with the
# show's actions, and the Door pinned to the bottom.
RSpec.describe "A ticketed show on a phone", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, owner: owner, stripe_account_id: "acct_x", payouts_enabled: true) }
  let(:listing) { create(:ticket_listing, organization: org) }

  before do
    create(:organization_role, :manager, user: owner, organization: org)
    TicketingProfile.for(org).update!(enabled: true, slug: "phone-#{org.id}")
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "pins the Door and a ⋯ menu of the other actions to the bottom" do
    get manage_ticket_listing_path(listing)
    expect(response).to have_http_status(:ok)
    bar = Nokogiri::HTML(response.body).at_css("[data-ticketing-phone-bar]")
    expect(bar["class"]).to include("sm:hidden", "fixed", "bottom-0")
    expect(bar.css("a").map { |a| a["href"] }).to include(door_path(listing))
    menu = Nokogiri::HTML(response.body).at_css("#ticket-listing-#{listing.id}-actions-sheet")
    expect(menu.text).to include("Orders", "Settings", "Visibility")
    expect(menu.text).not_to include("Scan tickets")
  end
end
