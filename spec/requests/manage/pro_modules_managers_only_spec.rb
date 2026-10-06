# frozen_string_literal: true

require "rails_helper"

# The Pro modules are the organization's managers' (Tim, 2026-10-06). A
# producer on a production's team keeps the free modules: shows, casting,
# sign-ups; never Money, Contracts, Reports, Staffing or Ticketing.
RSpec.describe "Pro modules are for managers", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, email_address: "owner@sg.example", password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let(:production) { create(:production, organization: org, name: "Boylesque") }
  let!(:show) { create(:show, production: production, date_and_time: 6.days.from_now.change(hour: 19)) }
  let(:producer) { create(:user, email_address: "producer@sg.example", password: password) }

  before do
    create(:organization_role, :manager, user: owner, organization: org)
    create(:organization_role, user: producer, organization: org, company_role: "member")
    ProductionPermission.create!(user: producer, production: production, role: "manager")
    TicketsAnswer.apply!(production, mode: "cocoscout", tiers: [ { "name" => "General", "price" => "20", "seats" => "60" } ])
  end

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
    post set_organization_path(id: org.id)
  end

  it "keeps a producer out of Money, Contracts, Reports, Staffing and Ticketing, and off the Pro nav" do
    sign_in(producer)
    get manage_production_show_path(production, show)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("On CocoScout")
    expect(response.body).not_to include(manage_money_show_financials_path(show), manage_money_index_path, manage_contracts_path, manage_reports_path, manage_staffing_index_path, manage_ticketing_path)
    expect(response.body).not_to include('tracking-wider text-gray-400">Pro</div>') # no Pro heading in the nav either

    [ manage_money_index_path, manage_money_show_financials_path(show), manage_contracts_path, manage_reports_path,
      manage_money_production_advances_path(production), manage_staffing_index_path, manage_ticketing_path ].each do |path|
      get path
      expect(response).to redirect_to(manage_path), "expected #{path} to send a producer home"
      expect(flash[:notice]).to eq("That part of CocoScout is for your organization's managers.")
    end
  end

  it "lets a manager in everywhere" do
    sign_in(owner)
    [ manage_money_index_path, manage_money_show_financials_path(show), manage_contracts_path, manage_reports_path, manage_ticketing_path ].each do |path|
      get path
      expect(response).to have_http_status(:ok), "expected #{path} to open for a manager"
    end
    get manage_production_show_path(production, show)
    expect(response.body).to include(manage_money_show_financials_path(show), manage_ticket_listing_path(show.ticket_listing))
  end
end
