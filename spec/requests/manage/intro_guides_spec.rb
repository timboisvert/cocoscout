# frozen_string_literal: true

require "rails_helper"

# Dismissible intro guides (shared/_intro_guide + Manage::GuidesController).
# Page guides show by default; the home what's-next panel is opt-in via
# production creation and covered in producer_setup_spec.
RSpec.describe "Intro guides", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }

  before do
    owner.update!(welcomed_production_at: Time.current)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "shows the casting guide by default and hides it after dismissal, with a way back" do
    get manage_casting_path
    expect(response.body).to include('data-intro-guide="casting_intro"')

    post manage_guide_dismiss_path("casting_intro"), headers: { "HTTP_REFERER" => manage_casting_path }
    expect(response).to redirect_to(manage_casting_path)

    get manage_casting_path
    expect(response.body).not_to include('data-intro-guide="casting_intro"')
    expect(response.body).to include("Show guide")

    post manage_guide_restore_path("casting_intro")
    get manage_casting_path
    expect(response.body).to include('data-intro-guide="casting_intro"')
  end

  it "shows the auditions guide on the auditions index" do
    get manage_signups_all_auditions_path
    expect(response.body).to include('data-intro-guide="auditions_intro"')
    expect(response.body).to include("How audition cycles work")
  end

  it "shows the auditions guide on the wizard's first screen only for a first cycle" do
    get manage_signups_auditions_wizard_path(production)
    expect(response.body).to include('data-intro-guide="auditions_intro"')

    create(:audition_cycle, production: production)
    get manage_signups_auditions_wizard_path(production)
    expect(response.body).not_to include('data-intro-guide="auditions_intro"')
  end

  it "shows the documents guide on the documents index" do
    get manage_org_documents_path
    expect(response.body).to include('data-intro-guide="documents_intro"')
    expect(response.body).to include("How documents work")
  end

  it "shows the shows guide on the shows index" do
    get manage_shows_path
    expect(response.body).to include('data-intro-guide="shows_intro"')
    expect(response.body).to include("How shows &amp; events work")
  end

  it "shows the courses guide on the courses index" do
    get manage_course_offerings_path
    expect(response.body).to include('data-intro-guide="courses_intro"')
    expect(response.body).to include("How courses work")
  end

  it "shows the contacts guide on the contacts directory" do
    get manage_contacts_path
    expect(response.body).to include('data-intro-guide="contacts_intro"')
    expect(response.body).to include("How contacts work")
  end

  it "shows the messages guide on the messages inbox" do
    get manage_messages_path
    expect(response.body).to include('data-intro-guide="messages_intro"')
    expect(response.body).to include("How messages work")
  end

  it "shows the signups guide on the sign-ups hub" do
    get manage_signups_path
    expect(response.body).to include('data-intro-guide="signups_intro"')
    expect(response.body).to include("Which kind of sign-up do you need?")
  end

  it "keeps guide state per user" do
    post manage_guide_dismiss_path("casting_intro")

    other = create(:user, password: password)
    create(:organization_role, :manager, user: other, organization: org)
    post handle_signin_path, params: { email_address: other.email_address, password: password }
    get select_organization_path # auto-picks their single org

    get manage_casting_path
    expect(response.body).to include('data-intro-guide="casting_intro"')
  end

  it "rejects keys outside the catalog" do
    post manage_guide_dismiss_path("made_up_guide")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(owner.reload.dismissed_guides).to be_empty
  end

  it "shows the what's-next home panel to anyone with a production until dismissed" do
    get manage_path
    expect(response.body).to include('data-intro-guide="production_next_steps"')

    post manage_guide_dismiss_path("production_next_steps")
    get manage_path
    expect(response.body).not_to include('data-intro-guide="production_next_steps"')
    expect(response.body).to include("Show guide")
  end

  it "hides the what's-next home panel when the org has no productions" do
    production.destroy!

    get manage_path
    expect(response.body).not_to include('data-intro-guide="production_next_steps"')
    expect(response.body).not_to include("Show guide")
  end
end
