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
    expect(response.body).not_to include("Schedule an event", "Schedule an event")

    get manage_production_shows_path(production)
    expect(response.body).not_to include("Schedule an event")

    get manage_show_path(production, show)
    expect(response.body).not_to include("Edit Show", "Duplicate Show", "Cancel Show")
    expect(response.body).to include("View Cast")
  end

  it "shows a production's manager the same pages with their buttons" do
    sign_in(producer)
    get manage_shows_path
    expect(response.body).to include("Schedule an event")
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

  # Every production page a viewer can open, read-only: none of the buttons
  # that lead to "You do not have permission". A manager sees them all.
  describe "the rest of the production pages" do
    let(:form) { create(:sign_up_form, :with_show, production: production, show: show) }
    let(:course) { create(:course_offering, production: production) }
    let(:role) { create(:role, production: production) }
    let(:vacancy) { create(:role_vacancy, :with_vacated_by, show: show, role: role) }
    let(:cycle) { create(:audition_cycle, production: production) }
    let(:document) { ProductionDocument.create!(production: production, title: "Handbook", body: "Be kind.") }

    before { create(:audition_request, audition_cycle: cycle) }

    # [page, the write controls on it]
    def pages
      [
        [ manage_signups_forms_path(production), [ "Create a Sign-up Form" ] ],
        [ manage_signups_form_path(production, form),
          [ manage_toggle_active_signups_form_path(production, form), manage_settings_signups_form_path(production, form),
            manage_edit_signups_form_path(production, form), manage_archive_signups_form_path(production, form) ] ],
        [ manage_preview_signups_form_path(production, form), [ manage_edit_signups_form_path(production, form) ] ],
        [ manage_course_offering_path(course),
          [ manage_edit_course_offering_path(course), manage_close_course_offering_path(course), "Add a student" ] ],
        [ manage_casting_production_path(production), [ manage_casting_settings_path(production) ] ],
        [ manage_casting_vacancy_path(production, vacancy),
          [ manage_cancel_casting_vacancy_path(production, vacancy), manage_reclaim_casting_vacancy_path(production, vacancy) ] ],
        [ manage_signups_auditions_cycle_requests_path(production, cycle),
          [ "Archive Selected", manage_toggle_voting_signups_auditions_cycle_path(production, cycle) ] ],
        [ manage_production_documents_path(production), [ manage_new_org_document_path(production_id: production.id) ] ],
        [ manage_production_document_path(production, document), [ edit_manage_production_document_path(production, document) ] ],
        [ manage_production_path(production), [ edit_manage_production_path(production) ] ],
        [ manage_signups_auditions_path(production), [ manage_form_signups_auditions_cycle_path(production, cycle) ] ],
        [ manage_casting_signups_auditions_cycle_path(production, cycle),
          [ manage_casting_select_signups_auditions_cycle_path(production, cycle), "Email Notifications" ] ],
        [ manage_schedule_auditions_signups_auditions_cycle_path(production, cycle), [ "Review &amp; notify" ] ]
      ]
    end

    it "renders the rest of what a viewer can open" do
      [ viewer, producer ].each do |user|
        sign_in(user)
        [ manage_signups_forms_archived_path(production), manage_course_offerings_path,
          manage_course_offering_attendance_path(course), manage_casting_availability_path(production),
          manage_show_modal_casting_availability_path(production, show),
          manage_casting_select_signups_auditions_cycle_path(production, cycle) ].each do |path|
          get path
          expect(response).to have_http_status(:ok), "#{path} gave #{response.status} for #{user == viewer ? 'viewer' : 'manager'}"
        end
      end
    end

    it "shows a viewer each page without its write buttons" do
      sign_in(viewer)
      pages.each do |path, controls|
        get path
        expect(response).to have_http_status(:ok), "#{path} gave #{response.status}"
        controls.each { |control| expect(response.body).not_to include(control), "#{path} still shows #{control}" }
      end
    end

    it "shows a production's manager the same pages with them" do
      sign_in(producer)
      pages.each do |path, controls|
        get path
        expect(response).to have_http_status(:ok), "#{path} gave #{response.status}"
        controls.each { |control| expect(response.body).to include(control), "#{path} is missing #{control}" }
      end
    end
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
