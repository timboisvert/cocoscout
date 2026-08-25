# frozen_string_literal: true

require "rails_helper"

# Casting someone who's double-booked (cast in an overlapping show anywhere in
# the org) or who marked themselves unavailable gets a 409 with the conflict
# details; the client shows the "Cast anyway" modal and resubmits with
# allow_conflicts.
RSpec.describe "Manage::Casting scheduling conflicts", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:production) { create(:production, organization: org) }
  let(:other_production) { create(:production, organization: org) }
  let(:showtime) { Time.zone.local(2026, 10, 2, 20, 0) }
  let(:show) { create(:show, production: production, date_and_time: showtime, duration_minutes: 120) }
  let(:role) { create(:role, production: production) }
  let(:person) { create(:person, name: "Busy Betty", email: "busy@example.com") }

  before do
    org.people << person
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  def double_book(member)
    other_show = create(:show, production: other_production, date_and_time: showtime + 1.hour, duration_minutes: 120)
    other_role = create(:role, production: other_production)
    create(:show_person_role_assignment, show: other_show, role: other_role, assignable: member)
  end

  describe "assign_person_to_role" do
    it "answers 409 with the conflicts instead of assigning" do
      double_book(person)

      post manage_casting_show_assign_person_path(production, show),
           params: { role_id: role.id, person_id: person.id }

      expect(response).to have_http_status(:conflict)
      body = JSON.parse(response.body)
      expect(body["conflict"]).to be(true)
      expect(body["member_name"]).to eq("Busy Betty")
      expect(body["conflicts"].first["message"]).to include("overlaps this show")
      expect(show.show_person_role_assignments.count).to eq(0)
    end

    it "assigns when allow_conflicts is passed (Cast anyway)" do
      double_book(person)

      post manage_casting_show_assign_person_path(production, show),
           params: { role_id: role.id, person_id: person.id, allow_conflicts: 1 }

      expect(response).to have_http_status(:ok)
      expect(show.show_person_role_assignments.count).to eq(1)
    end

    it "409s on declared unavailability too" do
      create(:show_availability, :unavailable, show: show, available_entity: person, note: "Out of town")

      post manage_casting_show_assign_person_path(production, show),
           params: { role_id: role.id, person_id: person.id }

      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)["conflicts"].first["message"]).to include("Out of town")
    end

    it "assigns cleanly when there is no conflict" do
      post manage_casting_show_assign_person_path(production, show),
           params: { role_id: role.id, person_id: person.id }

      expect(response).to have_http_status(:ok)
      expect(show.show_person_role_assignments.count).to eq(1)
    end

    it "does not conflict a member already cast in this show (second act, moves)" do
      first_role = create(:role, production: production)
      create(:show_person_role_assignment, show: show, role: first_role, assignable: person)
      double_book(person)

      post manage_casting_show_assign_person_path(production, show),
           params: { role_id: role.id, person_id: person.id }

      expect(response).to have_http_status(:ok)
      expect(show.show_person_role_assignments.count).to eq(2)
    end
  end

  describe "assign_guest_to_role" do
    it "checks a guest whose email matches a real person" do
      double_book(person)

      post manage_casting_show_assign_guest_path(production, show),
           params: { role_id: role.id, guest_name: "Betty", guest_email: "busy@example.com" }

      expect(response).to have_http_status(:conflict)
      expect(show.show_person_role_assignments.count).to eq(0)
    end

    it "never checks a pure guest" do
      post manage_casting_show_assign_guest_path(production, show),
           params: { role_id: role.id, guest_name: "Total Stranger", guest_email: "stranger@example.com" }

      expect(response).to have_http_status(:ok)
      expect(show.show_person_role_assignments.count).to eq(1)
    end
  end

  describe "replace_assignment" do
    it "checks the incoming member" do
      original = create(:person, name: "Original Olive")
      org.people << original
      assignment = create(:show_person_role_assignment, show: show, role: role, assignable: original)
      double_book(person)

      post manage_casting_show_replace_assignment_path(production, show),
           params: { assignment_id: assignment.id, new_person_id: person.id }

      expect(response).to have_http_status(:conflict)
      expect(assignment.reload).to be_persisted
    end
  end
end
