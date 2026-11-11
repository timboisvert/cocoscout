# frozen_string_literal: true

require "rails_helper"

# A location the organization no longer uses is archived: out of the
# locations list and the pickers, while everything that already points at it
# stays as it was. It can be restored.
RSpec.describe "Archiving a location", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }
  let!(:home) { create(:location, organization: org, name: "Main Stage") }
  let!(:library) { create(:location, organization: org, name: "Merlo Public Library") }
  let!(:old_show) { production.shows.create!(event_type: "show", date_and_time: 13.months.ago, location: library) }
  let!(:new_show) { production.shows.create!(event_type: "show", date_and_time: 2.weeks.from_now, location: home) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def location_options(body)
    Nokogiri::HTML(body).css("select[name='show[location_id]'] option").map(&:text)
  end

  it "archives from the location's page, behind an in-page modal" do
    get manage_location_path(library)
    expect(response.body).to include("Archive this location?", archive_manage_location_path(library))
    expect(response.body).not_to include("turbo_confirm", "data-turbo-confirm")

    patch archive_manage_location_path(library)

    expect(response).to redirect_to(section_manage_organization_path(org, section: "locations"))
    expect(library.reload).to be_archived
  end

  it "hides an archived location from the list, and shows it under Archived" do
    library.archive!

    get section_manage_organization_path(org, section: "locations")
    expect(response.body).to include("Main Stage", "Archived (1)")
    expect(response.body).not_to include("Merlo Public Library")

    get section_manage_organization_path(org, section: "locations", archived: 1)
    expect(response.body).to include("Merlo Public Library")
    expect(response.body).not_to include("Main Stage")
  end

  it "shows no filter until something is archived" do
    get section_manage_organization_path(org, section: "locations")

    expect(response.body).to include("Main Stage", "Merlo Public Library")
    expect(response.body).not_to include("Archived (")
  end

  it "leaves it out of a show's location picker" do
    library.archive!

    get edit_manage_production_show_path(production, new_show)

    expect(response).to have_http_status(:ok)
    expect(location_options(response.body)).to include("Main Stage")
    expect(location_options(response.body)).not_to include("Merlo Public Library")
  end

  it "keeps it on an old show: still shown, still selected when the show is edited, still there after a save" do
    library.archive!

    get manage_show_path(production, old_show)
    expect(response.body).to include("Merlo Public Library")

    get edit_manage_production_show_path(production, old_show)
    selected = Nokogiri::HTML(response.body).css("select[name='show[location_id]'] option[selected]").map(&:text)
    expect(selected).to eq([ "Merlo Public Library" ])

    patch manage_update_show_path(production, old_show), params: { show: { location_id: library.id, secondary_name: "One night only" } }
    expect(old_show.reload.location).to eq(library)
  end

  it "passes the default on and says so" do
    patch archive_manage_location_path(home)

    expect(library.reload).to be_default
    expect(flash[:notice]).to include("Main Stage was archived", "Merlo Public Library is now the default location")
  end

  it "restores" do
    library.archive!

    get manage_location_path(library)
    expect(response.body).to include("Restore this location?", restore_manage_location_path(library))

    patch restore_manage_location_path(library)

    expect(response).to redirect_to(manage_location_path(library))
    expect(library.reload).not_to be_archived
    get section_manage_organization_path(org, section: "locations")
    expect(response.body).to include("Merlo Public Library")
  end

  it "won't archive or restore another organization's location" do
    elsewhere = create(:location, organization: create(:organization), name: "Not ours")
    archived_elsewhere = create(:location, organization: elsewhere.organization, archived_at: 1.day.ago)

    patch archive_manage_location_path(elsewhere)
    expect(response).to have_http_status(:not_found)
    expect(elsewhere.reload).not_to be_archived

    patch restore_manage_location_path(archived_elsewhere)
    expect(response).to have_http_status(:not_found)
    expect(archived_elsewhere.reload).to be_archived
  end

  it "is for managers" do
    viewer = create(:user, password: password)
    create(:organization_role, user: viewer, organization: org, company_role: "viewer")
    get signout_path
    post handle_signin_path, params: { email_address: viewer.email_address, password: password }

    patch archive_manage_location_path(library)

    expect(library.reload).not_to be_archived
  end
end
