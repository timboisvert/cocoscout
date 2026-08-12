# frozen_string_literal: true

require "rails_helper"

# Availability notes ("out of town until 7", "can only do the second half")
# were collected from performers but never surfaced while casting. They now
# show in the talent-pool list and ride along in the assign-search payload.
RSpec.describe "Manage::Casting availability notes", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:production) { create(:production, organization: org) }
  let(:show) { create(:show, production: production) }
  let(:person) { create(:person, name: "Notey McNoteface") }

  before do
    org.people << person
    create(:talent_pool_membership, talent_pool: production.talent_pool, member: person)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  describe "the talent-pool list on the cast page" do
    it "shows the performer's availability note" do
      create(:show_availability, :available, show: show, available_entity: person, note: "Only after 8pm")

      get manage_casting_show_cast_path(production, show)
      expect(response.body).to include("Only after 8pm")
    end

    it "shows the note even when they're unavailable — that's when the why matters most" do
      create(:show_availability, :unavailable, show: show, available_entity: person, note: "Out of town")

      get manage_casting_show_cast_path(production, show)
      expect(response.body).to include("Out of town")
    end
  end

  describe "the assigned-cast cards on the roles side" do
    it "shows the note on the card once the person is cast" do
      # Deliberately NOT in the talent pool — the note can only be on their card.
      cast_person = create(:person, name: "Cast Withanote")
      org.people << cast_person
      role = create(:role, production: production)
      create(:show_person_role_assignment, show: show, role: role, assignable: cast_person)
      create(:show_availability, :available, show: show, available_entity: cast_person, note: "Leaving by 10pm sharp")

      get manage_casting_show_cast_path(production, show)
      expect(response.body).to include("Leaving by 10pm sharp")
    end
  end

  describe "search_people" do
    it "returns the note alongside the status, HTML-escaped for the JS renderers" do
      create(:show_availability, :available, show: show, available_entity: person, note: "8pm <late> ok")

      get manage_casting_search_people_path(production, q: "Notey", show_id: show.id)
      payload = JSON.parse(response.body)["people"].find { |p| p["name"] == "Notey McNoteface" }
      expect(payload["availability_status"]).to eq("available")
      expect(payload["availability_note"]).to eq("8pm &lt;late&gt; ok")
    end

    it "leaves the note null when the performer never wrote one" do
      create(:show_availability, :available, show: show, available_entity: person)

      get manage_casting_search_people_path(production, q: "Notey", show_id: show.id)
      payload = JSON.parse(response.body)["people"].find { |p| p["name"] == "Notey McNoteface" }
      expect(payload["availability_note"]).to be_nil
    end
  end
end
