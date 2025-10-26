require 'rails_helper'

RSpec.describe "My::Shows", type: :system do
  let!(:user) { create(:user) }
  let!(:person) { create(:person, user: user, email: user.email_address) }
  let(:production_company) { create(:production_company) }
  let(:production) { create(:production, production_company: production_company, name: "Hamilton") }
  let(:cast) { create(:cast, production: production) }
  let(:role) { create(:role, production: production, name: "Ensemble") }

  describe "shows index" do
    let!(:show1) { create(:show, production: production, date_and_time: 2.days.from_now, event_type: :show) }

    it "displays productions the user is cast in" do
      cast.people << person
      sign_in_as_person(user, person)
      visit "/my/shows"
      expect(page).to have_content("Hamilton")
    end

    it "shows no productions message when user is not in any casts" do
      sign_in_as_person(user, person)
      visit "/my/shows"
      expect(page).to have_content("You aren't a cast member of any shows.")
    end
  end

  describe "production detail page" do
    let!(:show1) { create(:show, production: production, date_and_time: 2.days.from_now, event_type: :show) }
    let!(:show2) { create(:show, production: production, date_and_time: 1.week.from_now, event_type: :rehearsal) }
    let!(:past_show) { create(:show, production: production, date_and_time: 1.week.ago) }

    it "displays upcoming shows for the production" do
      cast.people << person
      sign_in_as_person(user, person)
      visit "/my/shows/#{production.id}"

      expect(page).to have_content(show1.date_and_time.strftime("%B %d, %Y"))
      expect(page).to have_content(show2.date_and_time.strftime("%B %d, %Y"))
    end

    it "does not display past shows" do
      cast.people << person
      sign_in_as_person(user, person)
      visit "/my/shows/#{production.id}"

      expect(page).not_to have_content(past_show.date_and_time.strftime("%A, %B %-d, %Y"))
    end

    it "shows role assignment when person is assigned to a show" do
      cast.people << person
      create(:show_person_role_assignment, show: show1, person: person, role: role)

      sign_in_as_person(user, person)
      visit "/my/shows/#{production.id}"
      expect(page).to have_content("Ensemble")
    end

    it "shows 'aren't assigned' when person is not assigned to a show" do
      cast.people << person
      sign_in_as_person(user, person)
      visit "/my/shows/#{production.id}"
      expect(page).to have_content("aren't assigned")
    end
  end

  describe "individual show page" do
    let!(:show) { create(:show, production: production, date_and_time: 1.week.from_now) }
    let!(:assignment1) { create(:show_person_role_assignment, show: show, person: person, role: role) }
    let!(:other_person) { create(:person, name: "John Doe") }
    let!(:other_role) { create(:role, production: production, name: "Lead") }
    let!(:assignment2) { create(:show_person_role_assignment, show: show, person: other_person, role: other_role) }

    it "displays show details" do
      cast.people << person
      sign_in_as_person(user, person)
      visit "/my/shows/#{production.id}/#{show.id}"

      expect(page).to have_content(production.name)
      expect(page).to have_content(show.date_and_time.strftime("%B %d, %Y"))
    end

    it "displays all cast members for the show" do
      cast.people << person
      sign_in_as_person(user, person)
      visit "/my/shows/#{production.id}/#{show.id}"

      expect(page).to have_content("John Doe")
      expect(page).to have_content("Lead")
      expect(page).to have_content(person.name)
      expect(page).to have_content("Ensemble")
    end
  end

  describe "show event types" do
    let!(:show) { create(:show, production: production, date_and_time: 1.week.from_now, event_type: :show) }
    let!(:rehearsal) { create(:show, production: production, date_and_time: 2.weeks.from_now, event_type: :rehearsal) }
    let!(:meeting) { create(:show, production: production, date_and_time: 3.weeks.from_now, event_type: :meeting) }

    it "displays different event types" do
      cast.people << person
      sign_in_as_person(user, person)
      visit "/my/shows/#{production.id}"

      expect(page).to have_content("Show")
      expect(page).to have_content("Rehearsal")
      expect(page).to have_content("Meeting")
    end
  end
end
