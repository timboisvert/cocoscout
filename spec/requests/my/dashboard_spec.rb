# frozen_string_literal: true

require "rails_helper"

RSpec.describe "My::Dashboard", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user).tap { |p| user.update!(default_person: p) } }

  before { post handle_signin_path, params: { email_address: user.email_address, password: password } }

  describe "contracts waiting on your signature" do
    let!(:org) { create(:organization, :pro, name: "Stars & Garters") }
    let!(:contractor) { create(:contractor, organization: org, person: person) }
    let!(:production) { create(:production, organization: org, production_type: "third_party", name: "Random Memory") }

    def send_it!(contract)
      contract.update!(signing_state: :awaiting_send)
      contract.send_for_signature!
    end

    it "nudges with a Review & sign panel that opens the signing page" do
      contract = create(:contract, organization: org, production: production, contractor: contractor, signing_mode: :esign)
      send_it!(contract)

      get my_dashboard_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Signature required")
      expect(response.body).to include("Random Memory")
      expect(response.body).to include("Stars &amp; Garters needs you to review and sign this contract.")
      expect(response.body).to include(sign_contract_path(token: contract.reload.signing_token))
    end

    it "says nothing about contracts that aren't in their court" do
      create(:contract, organization: org, production: production, contractor: contractor, signing_mode: :esign) # still a draft
      create(:contract, :active, organization: org, production: production, contractor: contractor, signing_state: :executed)

      get my_dashboard_path
      expect(response.body).not_to include("Signature required")
    end
  end

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

  # Money she owes on a contract and hasn't paid by its due date gets a bar on
  # the dashboard — amber, in the standard alert-panel shape. Money merely
  # scheduled for later doesn't.
  describe "contract money already due" do
    let(:org) { create(:organization, :pro, name: "Stars & Garters") }
    let(:production) { create(:production, organization: org, name: "Dada Reinvents The Wheel") }
    let(:contractor) { create(:contractor, organization: org, person: person, email: person.email) }
    let!(:contract) { create(:contract, :active, organization: org, production: production, contractor: contractor) }

    it "shows an amber You-owe bar with a pay button for one overdue payment" do
      create(:contract_payment, contract: contract, direction: "incoming", amount: 50,
                                description: "Aug 19 event", due_date: 1.day.ago.to_date)

      get my_dashboard_path

      body = response.body
      expect(body).to include("Payment due")
      expect(body).to include("You owe $50.00")
      expect(body).to include("Dada Reinvents The Wheel")
      expect(body).to include("Pay $50.00")
      expect(body).to include("border-amber-200")
    end

    it "sums several overdue payments and points at My Contracts" do
      create(:contract_payment, contract: contract, direction: "incoming", amount: 50, due_date: 8.days.ago.to_date)
      create(:contract_payment, contract: contract, direction: "incoming", amount: 50, due_date: 1.day.ago.to_date)

      get my_dashboard_path

      expect(response.body).to include("You owe $100.00")
      expect(response.body).to include("View in My Contracts")
    end

    it "stays quiet when the money isn't due yet or is already paid" do
      create(:contract_payment, contract: contract, direction: "incoming", amount: 50, due_date: 1.week.from_now.to_date)
      create(:contract_payment, :paid, contract: contract, direction: "incoming", amount: 50, due_date: 1.week.ago.to_date)

      get my_dashboard_path
      expect(response.body).not_to include("You owe")
    end
  end

  describe "welcome guide" do
    it "greets the user with the welcome guide and holds the checklist back" do
      get my_dashboard_path

      expect(response.body).to include('data-intro-guide="talent_welcome"')
      expect(response.body).to include("Welcome to CocoScout!")
      expect(response.body).to include("Producing your own shows?")
    end

    it "keeps greeting org members until they dismiss it" do
      org = create(:organization, :pro)
      org.people << person

      get my_dashboard_path
      expect(response.body).to include('data-intro-guide="talent_welcome"')
      expect(response.body).to include("We&#39;ve upgraded how you get paid")
    end

    it "leaves quietly once dismissed, with a way back" do
      post guide_dismiss_path("talent_welcome")
      get my_dashboard_path

      expect(response.body).not_to include('data-intro-guide="talent_welcome"')
      expect(response.body).to include("Show it on the page")
      # The retired "Get started by completing your profile" checklist is gone
      # for good — profile nudges are the talent-pool alert panels now.
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
