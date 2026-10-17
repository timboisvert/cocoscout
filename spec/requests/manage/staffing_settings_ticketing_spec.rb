# frozen_string_literal: true

require "rails_helper"

# Staffing settings → Ticketing: whether staff see how many people to expect
# on their shifts (ShiftExpectedAttendance). The one thing staff get from
# Ticketing; greyed without Pro or while the box office is closed.
RSpec.describe "Staffing settings: Ticketing", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:owner_person) { create(:person, user: owner) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "is on by default, and says the box office is closed until it's open" do
    get manage_staffing_settings_section_path(section: "ticketing")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Show staff how many people to expect", "Your box office is closed, so there", "Open your box office")
    expect(response.body).to match(/id="staff_see_ticket_counts"[^>]*checked/)
    expect(response.body).to match(/id="staff_see_ticket_counts"[^>]*disabled/)
    expect(response.body).not_to include(">Save<")

    TicketingProfile.for(org).update!(enabled: true)
    get manage_staffing_settings_section_path(section: "ticketing")
    expect(response.body).not_to include("Your box office is closed")
    expect(response.body).not_to match(/id="staff_see_ticket_counts"[^>]*disabled/)
    expect(response.body).to include(">Save<")
  end

  it "turns the counts off and on" do
    TicketingProfile.for(org).update!(enabled: true)
    patch manage_staffing_settings_path, params: { updating_ticketing: "1" }
    expect(response).to redirect_to(manage_staffing_settings_section_path(section: "ticketing"))
    expect(org.reload.staff_see_ticket_counts).to be(false)
    expect(flash[:notice]).to eq("Staff don't see ticket counts on their shifts.")

    patch manage_staffing_settings_path, params: { updating_ticketing: "1", staff_see_ticket_counts: "1" }
    expect(org.reload.staff_see_ticket_counts).to be(true)
    expect(flash[:notice]).to eq("Staff see how many people to expect on their shifts.")
  end

  # Staffing is a Pro module itself, so the section's not-Pro state is never reached from here.
  it "stays behind the Pro gate on a free organization" do
    org.update!(comped_indefinitely: false)
    get manage_staffing_settings_section_path(section: "ticketing")
    expect(response).to have_http_status(:payment_required)
  end
end
