require 'rails_helper'

RSpec.describe "My::AuditionRequests", type: :system do
  let!(:user) { create(:user) }
  let!(:person) { create(:person, user: user, email: user.email_address) }
  let(:production_company) { create(:production_company) }
  let(:production) { create(:production, production_company: production_company, name: "The Phantom of the Opera") }

  describe "when user has no audition requests" do
    it "shows no sign-ups message" do
      sign_in_as_person(user, person)
      visit "/my/audition_requests"
      expect(page).to have_content("You haven't signed up for any auditions.")
    end
  end

  describe "when user has audition requests" do
    let!(:audition_cycle) { create(:audition_cycle, production: production, opens_at: 1.day.ago, closes_at: 1.week.from_now) }
    let!(:audition_request) { create(:audition_request, person: person, audition_cycle: audition_cycle, status: :unreviewed) }

    it "displays the audition request" do
      sign_in_as_person(user, person)
      visit "/my/audition_requests"

      expect(page).to have_content(production.name)
    end

    it "shows request status" do
      sign_in_as_person(user, person)
      visit "/my/audition_requests"

      expect(page).to have_content("Awaiting Review")
    end

    it "shows when auditions close" do
      sign_in_as_person(user, person)
      visit "/my/audition_requests"
      # Should see the production name
      expect(page).to have_content(production.name)
    end
  end

  describe "audition request statuses" do
    let!(:audition_cycle) { create(:audition_cycle, production: production, opens_at: 1.day.ago, closes_at: 1.week.from_now) }

    it "shows unreviewed status" do
      create(:audition_request, person: person, audition_cycle: audition_cycle, status: :unreviewed)

      sign_in_as_person(user, person)
      visit "/my/audition_requests"
      expect(page).to have_content("Awaiting Review")
    end

    it "shows passed status" do
      create(:audition_request, person: person, audition_cycle: audition_cycle, status: :passed)

      sign_in_as_person(user, person)
      visit "/my/audition_requests"
      expect(page).to have_content("No Audition Offered")
    end

    it "shows accepted status" do
      create(:audition_request, person: person, audition_cycle: audition_cycle, status: :accepted)

      sign_in_as_person(user, person)
      visit "/my/audition_requests"
      expect(page).to have_content("Audition Offered")
    end
  end

  describe "multiple audition requests" do
    let!(:call1) { create(:audition_cycle, production: production, opens_at: 1.day.ago, closes_at: 3.days.from_now) }
    let!(:call2) { create(:audition_cycle, production: production, opens_at: 1.day.ago, closes_at: 1.week.from_now) }
    let!(:request1) { create(:audition_request, person: person, audition_cycle: call1) }
    let!(:request2) { create(:audition_request, person: person, audition_cycle: call2) }

    it "displays all audition requests" do
      sign_in_as_person(user, person)
      visit "/my/audition_requests"

      expect(page).to have_content(call1.closes_at.strftime("%b %d, %Y"))
      expect(page).to have_content(call2.closes_at.strftime("%b %d, %Y"))
    end
  end

  describe "with answers to questions" do
    let!(:audition_cycle) { create(:audition_cycle, production: production) }
    let!(:question) { create(:question, questionable: audition_cycle, text: "What is your favorite role?") }
    let!(:audition_request) { create(:audition_request, person: person, audition_cycle: audition_cycle) }
    let!(:answer) { create(:answer, audition_request: audition_request, question: question, value: "Elphaba") }

    it "allows viewing submitted answers" do
      sign_in_as_person(user, person)
      visit "/my/audition_requests"

      expect(page).to have_content(production.name)
    end
  end
end
