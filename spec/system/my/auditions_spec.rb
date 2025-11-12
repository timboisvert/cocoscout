require 'rails_helper'

RSpec.describe "My::Auditions", type: :system do
  let!(:user) { create(:user) }
  let!(:person) { create(:person, user: user, email: user.email_address) }
  let(:production_company) { create(:production_company) }
  let(:production) { create(:production, production_company: production_company, name: "Les Miserables") }
  let(:audition_cycle) { create(:audition_cycle, production: production) }
  let(:audition_request) { create(:audition_request, person: person, audition_cycle: audition_cycle) }

  describe "when user has no auditions" do
    it "shows no upcoming auditions message" do
      sign_in_as_person(user, person)
      visit "/my/auditions"
      expect(page).to have_content("You don't have any upcoming auditions.")
    end
  end

  describe "when user has upcoming auditions" do
    let!(:upcoming_session) { create(:audition_session, :upcoming, production: production) }
    let!(:upcoming_audition) { create(:audition, person: person, audition_request: audition_request, audition_session: upcoming_session) }

    it "displays upcoming auditions by default" do
      sign_in_as_person(user, person)
      visit "/my/auditions"

      expect(page).to have_content(production.name)
      expect(page).to have_content(upcoming_session.start_at.strftime("%b %d, %Y"))
    end

    it "shows audition time" do
      sign_in_as_person(user, person)
      visit "/my/auditions"

      expect(page).to have_content(upcoming_session.start_at.strftime("%-l:%M %p"))
    end

    it "shows location information" do
      sign_in_as_person(user, person)
      visit "/my/auditions"

      expect(page).to have_content(upcoming_session.location.name)
    end
  end

  describe "when user has past auditions" do
    let!(:past_session) { create(:audition_session, :past, production: production) }
    let!(:past_audition) { create(:audition, person: person, audition_request: audition_request, audition_session: past_session) }

    it "does not show past auditions in upcoming view" do
      sign_in_as_person(user, person)
      visit "/my/auditions?auditions_filter=upcoming"

      expect(page).not_to have_content(past_session.start_at.strftime("%A, %B %-d, %Y"))
    end

    it "shows past auditions when filtered" do
      sign_in_as_person(user, person)
      visit "/my/auditions?auditions_filter=past"

      expect(page).to have_content(past_session.start_at.strftime("%b %d, %Y"))
    end
  end

  describe "filtering auditions" do
    let!(:upcoming_session) { create(:audition_session, :upcoming, production: production) }
    let!(:upcoming_audition) { create(:audition, person: person, audition_request: audition_request, audition_session: upcoming_session) }
    let!(:past_session) { create(:audition_session, :past, production: production) }
    let!(:past_audition) { create(:audition, person: person, audition_request: audition_request, audition_session: past_session) }

    it "allows switching between upcoming and past" do
      sign_in_as_person(user, person)
      visit "/my/auditions?auditions_filter=upcoming"
      expect(page).to have_content(upcoming_session.start_at.strftime("%b %d, %Y"))

      visit "/my/auditions?auditions_filter=past"
      expect(page).to have_content(past_session.start_at.strftime("%b %d, %Y"))
    end

    it "remembers filter selection in session" do
      sign_in_as_person(user, person)
      visit "/my/auditions?auditions_filter=past"
      visit "/my/auditions"  # No filter param

      # Should still show past auditions due to session memory
      expect(page).to have_content(past_session.start_at.strftime("%b %d, %Y"))
    end
  end

  describe "multiple auditions" do
    let!(:session1) { create(:audition_session, :upcoming, production: production, start_at: 2.days.from_now) }
    let!(:session2) { create(:audition_session, :upcoming, production: production, start_at: 1.week.from_now) }
    let!(:audition1) { create(:audition, person: person, audition_request: audition_request, audition_session: session1) }
    let!(:audition2) { create(:audition, person: person, audition_request: audition_request, audition_session: session2) }

    it "displays multiple upcoming auditions in chronological order" do
      sign_in_as_person(user, person)
      visit "/my/auditions"

      expect(page).to have_content(session1.start_at.strftime("%b %d, %Y"))
      expect(page).to have_content(session2.start_at.strftime("%b %d, %Y"))

      # Check order (earlier date should come first)
      expect(page.body.index(session1.start_at.strftime("%b %d, %Y"))).to be < page.body.index(session2.start_at.strftime("%b %d, %Y"))
    end
  end
end
