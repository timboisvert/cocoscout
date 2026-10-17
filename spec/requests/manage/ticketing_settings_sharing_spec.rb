# frozen_string_literal: true

require "rails_helper"

# Ticketing settings → Who sees sales: what a production team manager, a
# production team viewer and the cast see of a production's sales
# (TicketSalesAccess). Managers always see everything.
RSpec.describe "Ticketing settings: Who sees sales", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }

  before do
    create(:organization_role, :manager, user: owner, organization: org)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    get manage_path
  end

  it "shows the three choices with the defaults picked" do
    get manage_ticketing_settings_section_path(section: "sharing")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Who sees sales", "Production team managers", "Production team viewers", ">Cast<",
                                     "Everyone on the production", "The cast of each date", "Staffing settings → Ticketing",
                                     manage_staffing_settings_section_path(section: "ticketing"))
    expect(response.body).to match(/id="ticketing_profile_team_manager_sales_everything"[^>]*checked/)
    expect(response.body).to match(/id="ticketing_profile_team_viewer_sales_numbers"[^>]*checked/)
    expect(response.body).to match(/id="ticketing_profile_cast_sales_production_cast"[^>]*checked/)
    expect(response.body).not_to include("producer")
  end

  it "saves the choices and reads them back" do
    patch manage_ticketing_settings_sharing_path, params: { ticketing_profile: { team_manager_sales: "numbers", team_viewer_sales: "nothing", cast_sales: "show_cast" } }
    expect(response).to redirect_to(manage_ticketing_settings_section_path(section: "sharing"))
    profile = TicketingProfile.for(org)
    expect([ profile.team_manager_sales, profile.team_viewer_sales, profile.cast_sales ]).to eq(%w[numbers nothing show_cast])
    expect(flash[:notice]).to eq("Saved. Production team managers see the numbers and the link, production team viewers nothing, and the cast of each date sees its count and link.")
    expect(profile.team_level("manager")).to eq(:numbers)
    expect(profile.team_level("viewer")).to be_nil
  end

  it "refuses a value that isn't a choice" do
    patch manage_ticketing_settings_sharing_path, params: { ticketing_profile: { team_manager_sales: "everything", team_viewer_sales: "everything", cast_sales: "production_cast" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(TicketingProfile.for(org).team_viewer_sales).to eq("numbers")
  end
end
