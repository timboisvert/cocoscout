# frozen_string_literal: true

require "rails_helper"

RSpec.describe "My::Tasks", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user).tap { |p| user.update!(default_person: p) } }
  let(:organization) { create(:organization, :pro) }
  let(:production) { create(:production, organization: organization) }
  let(:pool) { create(:talent_pool, production: production) }

  before do
    TalentPoolMembership.create!(talent_pool: pool, member: person)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  describe "GET /my/tasks" do
    it "renders only the sections that have items" do
      create(:show, production: production, date_and_time: 1.week.from_now)

      get my_tasks_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("My Tasks")
      expect(response.body).to include("Availability requests")
      expect(response.body).not_to include("Sign-ups")
      expect(response.body).not_to include("Questionnaires")
      expect(response.body).not_to include("Availability you&#39;ve given")
    end

    it "shows an unset-status availability row as still awaiting" do
      show = create(:show, production: production, date_and_time: 1.week.from_now)
      create(:show_availability, show: show, available_entity: person, status: :unset)

      get my_tasks_path
      expect(response.body).to include("Availability requests")
    end

    it "surfaces answered availability in the always-findable 'Availability you've given' section" do
      show = create(:show, production: production, date_and_time: 1.week.from_now)
      create(:show_availability, :available, show: show, available_entity: person)

      get my_tasks_path
      expect(response.body).to include("Availability you&#39;ve given")
      expect(response.body).to include("change your answer any time")
      expect(response.body).to include(my_availability_calendar_path)
      expect(response.body).not_to include("Availability requests")
    end

    it "keeps a future signed-up show visible in the Sign-ups section" do
      show = create(:show, production: production, date_and_time: 2.weeks.from_now)
      form = create(:sign_up_form, production: production)
      instance = create(:sign_up_form_instance, sign_up_form: form, show: show, status: "open")
      slot = create(:sign_up_slot, sign_up_form: form, sign_up_form_instance: instance)
      create(:sign_up_registration, sign_up_slot: slot, sign_up_form_instance: instance, person: person)

      get my_tasks_path
      expect(response.body).to include("Sign-ups")
      expect(response.body).to include(show.production.name)
    end

    it "shows the caught-up state when nothing needs a response" do
      # Pool membership exists but there are no shows/questionnaires at all.
      get my_tasks_path
      expect(response.body).to include("all caught up")
      expect(response.body).to include("Nothing needs your response right now")
    end
  end

  describe "legacy redirects" do
    it "redirects /my/requests and /my/availability to /my/tasks" do
      get "/my/requests"
      expect(response).to redirect_to("/my/tasks")
      get "/my/availability"
      expect(response).to redirect_to("/my/tasks")
    end
  end

  describe "POST /my/tasks/signup/:show_id" do
    let!(:show) { create(:show, production: production, date_and_time: 2.weeks.from_now) }
    let!(:form) { create(:sign_up_form, production: production) }
    let!(:instance) { create(:sign_up_form_instance, sign_up_form: form, show: show, status: "open") }
    let!(:slot) { create(:sign_up_slot, sign_up_form: form, sign_up_form_instance: instance) }

    it "creates a confirmed registration and redirects back to My Tasks" do
      post my_task_sign_up_path(show_id: show.id), params: { person_id: person.id }

      expect(response).to redirect_to(my_tasks_path)
      registration = SignUpRegistration.find_by(person: person, sign_up_slot: slot)
      expect(registration.status).to eq("confirmed")
    end

    it "reactivates a cancelled registration on re-signup" do
      registration = create(:sign_up_registration, :cancelled, sign_up_slot: slot,
                            sign_up_form_instance: instance, person: person, cancelled_at: Time.current)

      post my_task_sign_up_path(show_id: show.id), params: { person_id: person.id }

      expect(registration.reload.status).to eq("confirmed")
      expect(registration.cancelled_at).to be_nil
    end
  end

  describe "POST /my/tasks/decline/:show_id" do
    let!(:show) { create(:show, production: production, date_and_time: 2.weeks.from_now) }
    let!(:form) { create(:sign_up_form, production: production) }
    let!(:instance) { create(:sign_up_form_instance, sign_up_form: form, show: show, status: "open") }
    let!(:slot) { create(:sign_up_slot, sign_up_form: form, sign_up_form_instance: instance) }

    it "cancels the registration and records an unavailable answer" do
      registration = create(:sign_up_registration, sign_up_slot: slot, sign_up_form_instance: instance, person: person)

      post my_task_decline_signup_path(show_id: show.id), params: { person_id: person.id }

      expect(response).to redirect_to(my_tasks_path)
      expect(registration.reload.status).to eq("cancelled")
      availability = ShowAvailability.find_by(show: show, available_entity: person)
      expect(availability.status).to eq("unavailable")
    end
  end
end
