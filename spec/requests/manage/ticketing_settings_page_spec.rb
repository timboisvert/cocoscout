# frozen_string_literal: true

require "rails_helper"

# Ticketing settings → Box office page (Tim, 2026-10-18): the layout, a
# welcome line, the address switch and a wide image.
RSpec.describe "Ticketing settings: the box office page", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true) } }

  before do
    create(:organization_role, :manager, user: owner, organization: org)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "shows the section and saves the layout, the welcome line, the address switch and a wide image" do
    get manage_ticketing_settings_section_path(section: "page")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Box office page", "Dates first", "Poster wall", "A line of welcome", "Wide image")

    patch manage_ticketing_settings_page_path, params: { ticketing_profile: {
      box_office_layout: "posters", welcome_line: "  Chicago's home for the strange  ", show_address: "0",
      wide_image: fixture_file_upload("test_image.png", "image/png")
    } }
    expect(response).to redirect_to(manage_ticketing_settings_section_path(section: "page"))
    profile.reload
    expect(profile.box_office_layout).to eq("posters")
    expect(profile.welcome_line).to eq("Chicago's home for the strange")
    expect(profile.show_address).to be(false)
    expect(profile.wide_image).to be_attached

    patch manage_ticketing_settings_page_path, params: { remove_wide_image: "1", ticketing_profile: { box_office_layout: "dates", welcome_line: "" } }
    profile.reload
    expect(profile.welcome_line).to be_nil
    expect(profile.box_office_layout).to eq("dates")

    patch manage_ticketing_settings_page_path, params: { ticketing_profile: { box_office_layout: "mosaic" } }
    expect(response).to have_http_status(:unprocessable_content)
  end
end
