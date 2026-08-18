# frozen_string_literal: true

require "rails_helper"

RSpec.describe "My::Dashboard", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user).tap { |p| user.update!(default_person: p) } }

  before { post handle_signin_path, params: { email_address: user.email_address, password: password } }

  describe "staff onboarding prompts" do
    it "prompts to finish onboarding for an incomplete staff position, linking to that org's onboarding" do
      org = create(:organization, :pro)
      create(:organization_staff_member, organization: org, person: person, onboarding_state: "invited")

      get my_dashboard_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Finish setting up")
      expect(response.body).to include(org.name)
      expect(response.body).to include(my_onboarding_path(org.id))
    end

    it "shows a separate prompt per organization" do
      org_a = create(:organization, :pro, name: "Alpha Theater")
      org_b = create(:organization, :pro, name: "Beta Playhouse")
      create(:organization_staff_member, organization: org_a, person: person, onboarding_state: "invited")
      create(:organization_staff_member, organization: org_b, person: person, onboarding_state: "invited")

      get my_dashboard_path
      expect(response.body).to include("Alpha Theater").and include("Beta Playhouse")
      expect(response.body).to include(my_onboarding_path(org_a.id)).and include(my_onboarding_path(org_b.id))
    end

    it "does not prompt once onboarding is complete (accepted + bank connected)" do
      person.update!(stripe_account_id: "acct_x", payouts_enabled: true)
      org = create(:organization, :pro)
      create(:organization_staff_member, organization: org, person: person,
                                         onboarding_state: "invited", acknowledged_at: Time.current)

      get my_dashboard_path
      expect(response.body).not_to include("Finish setting up your staff")
    end
  end

  describe "welcome guide" do
    it "greets the user with the welcome guide and holds the checklist back" do
      get my_dashboard_path

      expect(response.body).to include('data-intro-guide="talent_welcome"')
      expect(response.body).to include("Welcome to CocoScout!")
      expect(response.body).to include("Producing your own shows?")
      expect(response.body).not_to include("Get started by completing your profile")
    end

    it "keeps greeting org members until they dismiss it" do
      org = create(:organization, :pro)
      org.people << person

      get my_dashboard_path
      expect(response.body).to include('data-intro-guide="talent_welcome"')
      expect(response.body).to include("We&#39;ve upgraded how you get paid")
    end

    it "swaps to the checklist once dismissed, with a way back" do
      post guide_dismiss_path("talent_welcome")
      get my_dashboard_path

      expect(response.body).not_to include('data-intro-guide="talent_welcome"')
      expect(response.body).to include("Show it on the page")
      expect(response.body).to include("Get started by completing your profile")
    end

    it "dismisses the checklist through the guide system" do
      post guide_dismiss_path("talent_welcome")
      post guide_dismiss_path("profile_checklist")
      get my_dashboard_path

      expect(response.body).not_to include("Get started by completing your profile")
    end
  end

  describe "open tasks summary card" do
    let(:organization) { create(:organization, :pro) }
    let(:production) { create(:production, organization: organization) }
    let(:pool) { create(:talent_pool, production: production) }

    before { TalentPoolMembership.create!(talent_pool: pool, member: person) }

    it "shows the count, breakdown, and a link to My Tasks when tasks are waiting" do
      create(:show, production: production, date_and_time: 1.week.from_now)
      create(:show, production: production, date_and_time: 2.weeks.from_now)
      questionnaire = create(:questionnaire, production: production)
      QuestionnaireInvitation.create!(questionnaire: questionnaire, invitee: person)

      get my_dashboard_path
      expect(response.body).to include("3 tasks waiting")
      expect(response.body).to include("2 availability requests")
      expect(response.body).to include("1 questionnaire")
      expect(response.body).to include(my_tasks_path)
    end

    it "renders nothing when the user is caught up" do
      get my_dashboard_path
      expect(response.body).not_to include("tasks waiting")
      expect(response.body).not_to include("Go to My Tasks")
    end
  end
end
