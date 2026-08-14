# frozen_string_literal: true

require "rails_helper"

# The manage home summary boxes only appear when they have something to say.
RSpec.describe "Manage home summary boxes", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }
  let!(:show) { create(:show, production: production, date_and_time: 1.week.from_now) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  context "on Pro with nothing going on" do
    let!(:org) { create(:organization, :pro, owner: owner) }

    it "hides both boxes" do
      get manage_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Event Registrations")
      expect(response.body).not_to include("Audition Sign-ups")
    end
  end

  context "on Pro with an open audition cycle" do
    let!(:org) { create(:organization, :pro, owner: owner) }
    let!(:cycle) { create(:audition_cycle, production: production, active: true) }
    let!(:request_record) { create(:audition_request, audition_cycle: cycle) }

    it "shows the Audition Sign-ups box" do
      get manage_path

      expect(response.body).to include("Audition Sign-ups")
    end
  end

  context "with a live sign-up form" do
    let!(:org) { create(:organization, :pro, owner: owner) }
    let!(:sign_up_form) { create(:sign_up_form, production: production) }
    let!(:instance) { create(:sign_up_form_instance, sign_up_form: sign_up_form, show: show) }

    it "shows the Event Registrations box" do
      get manage_path

      expect(response.body).to include("Event Registrations")
    end
  end

  context "on the Producer plan with no sign-up forms" do
    let!(:org) { create(:organization, owner: owner) }

    it "shows neither summary box" do
      get manage_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Event Registrations")
      expect(response.body).not_to include("Audition Sign-ups")
    end
  end
end
