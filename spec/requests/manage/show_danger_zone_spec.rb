# frozen_string_literal: true

require "rails_helper"

# The Danger Zone opens Cancel or move this date (Tim, 2026-11-27), offers
# Bring this date back once canceled, and deletes a date nobody counts on
# from its own small modal.
RSpec.describe "Show Danger Zone", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }
  let!(:location) { create(:location, organization: org) }
  let!(:show) { production.shows.create!(event_type: "show", date_and_time: 2.weeks.from_now, location: location) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "links to Cancel or move this date, and renders the delete modal" do
    get edit_manage_production_show_path(production, show)

    expect(response.body).to include(manage_new_date_change_path(production, show))
    expect(response.body).to include(%(id="delete-date-#{show.id}"))
  end

  it "cancels the show from the cancel modal form" do
    patch manage_cancel_show_path(production, show), params: { scope: "this" }

    expect(response).to have_http_status(:see_other)
    expect(show.reload.canceled).to be(true)
  end

  it "offers Bring this date back once canceled" do
    show.update!(canceled: true)
    get edit_manage_production_show_path(production, show)

    expect(response.body).to include(manage_new_date_restore_path(production, show))
    expect(response.body).not_to include(manage_new_date_change_path(production, show))
  end

  it "deletes the show from the delete modal form" do
    expect {
      delete manage_delete_show_path(production, show), params: { scope: "this" }
    }.to change(Show, :count).by(-1)
    expect(response).to have_http_status(:see_other)
  end
end
