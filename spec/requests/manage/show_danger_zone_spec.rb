# frozen_string_literal: true

require "rails_helper"

# Cancel / delete / uncancel moved from a separate page into in-place modals on
# the Danger Zone tab. These pin that the edit screen renders the modals and
# that each still drives the existing controller actions.
RSpec.describe "Show Danger Zone", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }
  let!(:location) { create(:location, organization: org) }
  let!(:show) { production.shows.create!(event_type: "show", date_and_time: 2.weeks.from_now, location: location) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "renders the in-place cancel and delete modals (no page detour)" do
    get edit_manage_production_show_path(production, show)

    expect(response.body).to include('id="danger-cancel-modal"')
    expect(response.body).to include('id="danger-delete-modal"')
    expect(response.body).to include("Notify cast by email")
  end

  it "cancels the show from the cancel modal form" do
    patch manage_cancel_show_path(production, show), params: { scope: "this", notify_cast: "0" }

    expect(response).to have_http_status(:see_other)
    expect(show.reload.canceled).to be(true)
  end

  it "shows the uncancel (not cancel) modal once canceled" do
    show.update!(canceled: true)
    get edit_manage_production_show_path(production, show)

    expect(response.body).to include('id="danger-uncancel-modal"')
    expect(response.body).not_to include('id="danger-cancel-modal"')
  end

  it "deletes the show from the delete modal form" do
    expect {
      delete manage_delete_show_path(production, show), params: { scope: "this" }
    }.to change(Show, :count).by(-1)
    expect(response).to have_http_status(:see_other)
  end
end
