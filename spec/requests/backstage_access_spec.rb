# frozen_string_literal: true

require "rails_helper"

# Accessibility for performers and crew (accessibility plan §3, V1.4): the
# venue's "Getting in and backstage" card on a cast member's date and an
# audition, and a private access need, for an audition or a production, seen
# only by the production team managers and deleted when that ends.
RSpec.describe "Backstage access", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:location) { create(:location, organization: org, name: "The Lodge", access_email: "access@lodge.example") }
  let(:room) { location.default_room }
  let(:production) { create(:production, organization: org, name: "Boylesque") }
  let!(:show) { create(:show, production: production, location: location, location_space: room, date_and_time: 5.days.from_now.change(hour: 19)) }
  let(:performer) { create(:user, password: password) }
  let!(:person) { create(:person, user: performer, name: "Jamie Cruz", email: performer.email_address).tap { |p| performer.update!(default_person: p) } }
  let(:viewer) { create(:user, password: password) }

  before do
    create(:organization_role, :manager, user: owner, organization: org)
    location.access_answers.create!(feature_key: "step_free_stage", answer: "yes", note: "Ramp by the stage door")
    location.access_answers.create!(feature_key: "accessible_dressing_room", answer: "no")
    location.access_answers.create!(feature_key: "assistive_listening", answer: "yes") # guests only: not on the card
  end

  def sign_in(user)
    get signout_path
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  # Cast and published (casting finalized), so the assignment is theirs to see.
  def cast!
    create(:show_person_role_assignment, show: show, assignable: person, role: create(:role, production: production, name: "Emcee"))
    show.update!(casting_finalized_at: Time.current)
  end

  it "shows a cast member the venue's backstage answers and lets them leave a note only managers see" do
    cast!
    sign_in(performer)
    get my_show_path(show)
    expect(response.body).to include("Getting in and backstage", "Step-free route to the stage", "Ramp by the stage door",
                                     "Accessible dressing room", "access@lodge.example", "I have an access need for this production")
    expect(response.body).not_to include("Assistive listening")

    patch my_show_access_need_path(show), params: { access_need: { needed: "1", note: "I use a wheelchair; a ramp to the stage, please." } }
    expect(response).to redirect_to(my_show_path(show))
    expect(flash[:notice]).to eq("Your access need has been saved. Only the production team managers can see it.")
    expect(AccessNeed.for_productions.find_by(person: person, production: production).note).to eq("I use a wheelchair; a ramp to the stage, please.")

    sign_in(owner)
    get manage_production_path(production)
    expect(response.body).to include("data-production-access-needs", "Jamie Cruz", "a ramp to the stage, please")

    create(:organization_role, user: viewer, organization: org, company_role: "viewer")
    sign_in(viewer)
    get manage_production_path(production)
    expect(response.body).not_to include("data-production-access-needs", "a ramp to the stage, please")

    sign_in(performer)
    patch my_show_access_need_path(show), params: { access_need: { needed: "0", note: "ignored" } }
    expect(flash[:notice]).to eq("Your access need has been removed.")
    expect(AccessNeed.count).to eq(0)
  end

  it "takes no note from someone who isn't on the date, or whose casting isn't published yet" do
    sign_in(performer)
    patch my_show_access_need_path(show), params: { access_need: { needed: "1", note: "Hello" } }
    expect(response).to have_http_status(:redirect)
    create(:show_person_role_assignment, show: show, assignable: person, role: create(:role, production: production, name: "Emcee"))
    patch my_show_access_need_path(show), params: { access_need: { needed: "1", note: "Hello" } }
    expect(AccessNeed.count).to eq(0)
  end

  it "saves an audition's access need with the request, for the managers' eyes only" do
    cycle = create(:audition_cycle, production: production, form_reviewed: true, token: "BACKSTAGE1")
    sign_in(performer)
    get my_submit_audition_request_form_path(token: cycle.token)
    expect(response.body).to include("I have an access need for this audition")

    post my_submit_submit_audition_request_form_path(token: cycle.token),
         params: { question: {}, access_need: { needed: "1", note: "Seated audition, please." } }
    expect(response).to redirect_to(my_submit_audition_request_success_path(token: cycle.token))
    need = AccessNeed.find_by!(person: person, audition_cycle: cycle)
    expect(need.note).to eq("Seated audition, please.")

    sign_in(owner)
    get manage_signups_auditions_cycle_request_path(production, cycle, AuditionRequest.last)
    expect(response.body).to include("Access need", "Seated audition, please.")
  end

  it "deletes a note once its audition cycle or production is over, and keeps the rest" do
    cycle = create(:audition_cycle, production: production, form_reviewed: true, token: "BACKSTAGE2")
    ended = create(:production, organization: org, name: "Last Season")
    create(:show, production: ended, date_and_time: 3.days.ago)
    keep_production = AccessNeed.create!(person: person, production: production, note: "Keep me")
    keep_audition = AccessNeed.create!(person: person, production: production, audition_cycle: cycle, note: "Still auditioning")
    gone_production = AccessNeed.create!(person: person, production: ended, note: "Over")

    PurgeAccessRequestsJob.perform_now
    expect(AccessNeed.where(id: [ keep_production.id, keep_audition.id ]).count).to eq(2)
    expect(AccessNeed.exists?(gone_production.id)).to be(false)

    cycle.update!(active: false)
    PurgeAccessRequestsJob.perform_now
    expect(AccessNeed.exists?(keep_audition.id)).to be(false)
    expect(AccessNeed.exists?(keep_production.id)).to be(true)
  end
end
