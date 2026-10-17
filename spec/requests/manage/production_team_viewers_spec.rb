# frozen_string_literal: true

require "rails_helper"

# Production team viewers look; managers change things (Tim, 2026-10-17).
# A viewer sees the shows, the cast and the sign-ups, without the buttons
# that change them, and the changes themselves are refused.
RSpec.describe "Production team viewers", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, owner: owner) }
  let(:production) { create(:production, organization: org, name: "Boylesque") }
  let!(:show) { create(:show, production: production, date_and_time: 6.days.from_now.change(hour: 19)) }
  let(:viewer) { create(:user, password: password) }
  let(:producer) { create(:user, password: password) }

  before do
    create(:organization_role, :manager, user: owner, organization: org)
    create(:organization_role, user: viewer, organization: org, company_role: "member")
    create(:organization_role, user: producer, organization: org, company_role: "member")
    ProductionPermission.create!(user: viewer, production: production, role: "viewer")
    ProductionPermission.create!(user: producer, production: production, role: "manager")
  end

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
    post set_organization_path(id: org.id)
  end

  it "shows a viewer the shows without Schedule Event or the event's Manage box" do
    sign_in(viewer)
    get manage_shows_path
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Schedule Event", "Schedule an event")

    get manage_production_shows_path(production)
    expect(response.body).not_to include("Schedule Event")

    get manage_show_path(production, show)
    expect(response.body).not_to include("Edit Show", "Duplicate Show", "Cancel Show")
    expect(response.body).to include("View Cast")
  end

  it "shows a production's manager the same pages with their buttons" do
    sign_in(producer)
    get manage_shows_path
    expect(response.body).to include("Schedule Event")
    get manage_show_path(production, show)
    expect(response.body).to include("Edit Show", "Manage Cast")
  end

  it "gives a viewer the cast to read, not the casting board" do
    sign_in(viewer)
    get manage_casting_show_cast_path(production, show)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Cast So Far")
    expect(response.body).not_to include("Make Changes", "Add Guest")
  end

  it "refuses a viewer's changes to casting, settings, sign-ups, people and the organization's settings" do
    person = create(:person)
    org.people << person
    location = create(:location, organization: org)
    sign_in(viewer)

    post manage_casting_show_finalize_path(production, show)
    expect(response).to redirect_to(manage_path)
    expect(show.reload.casting_finalized?).to be(false)

    patch manage_update_casting_settings_path(production), params: { production: { name: "Changed" } }
    expect(response).to redirect_to(manage_path)

    expect { post manage_create_signups_form_path(production), params: { sign_up_form: { name: "Open mic" } } }
      .not_to change(SignUpForm, :count)
    expect(response).to redirect_to(manage_path)

    post remove_from_organization_manage_person_path(person)
    expect(response).to redirect_to(manage_path)
    expect(org.people.reload).to include(person)

    expect { post "/manage/locations/#{location.id}/spaces", params: { location_space: { name: "Back room" } } }
      .not_to change(LocationSpace, :count)

    patch manage_course_settings_tax_path
    expect(response).to redirect_to(manage_path)
  end

  it "lists only the productions someone manages" do
    other = create(:production, organization: org)
    ProductionPermission.create!(user: viewer, production: other, role: "manager")
    Current.organization = org
    expect(viewer.managed_productions).to contain_exactly(other)
    expect(owner.managed_productions).to include(production, other)
  ensure
    Current.organization = nil
  end
end
