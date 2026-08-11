# frozen_string_literal: true

require "rails_helper"

# Multi-tenant isolation on the manage side: a manager in org A must not be
# able to read or mutate org B's records by supplying foreign ids — even when
# the URL carries their own (correctly authorized) production id. Each example
# here pins one of the cross-org holes closed in the Aug 2026 tenancy sweep.
RSpec.describe "Cross-org isolation (manage)", type: :request do
  let(:password) { "Password123!" }

  # Attacker: a manager in their own legitimate org.
  let(:attacker) { create(:user, password: password) }
  let!(:attacker_person) { create(:person, user: attacker).tap { |p| attacker.update!(default_person: p) } }
  let!(:org) { create(:organization, :pro, owner: attacker) }
  let!(:org_role) { create(:organization_role, :manager, user: attacker, organization: org) }
  let!(:production) { create(:production, organization: org) }

  # Victim org with the records under attack.
  let(:victim_owner) { create(:user) }
  let!(:victim_org) { create(:organization, :pro, owner: victim_owner) }
  let!(:victim_production) { create(:production, organization: victim_org) }

  before do
    org.people << attacker_person unless org.people.include?(attacker_person)
    post handle_signin_path, params: { email_address: attacker.email_address, password: password }
  end

  describe "audition cycles (C-3)" do
    let!(:victim_cycle) { create(:audition_cycle, production: victim_production) }

    it "404s on show/update/destroy with my production id + a foreign cycle id" do
      get manage_signups_auditions_cycle_path(production, victim_cycle)
      expect(response).to have_http_status(:not_found)

      expect {
        delete manage_destroy_signups_auditions_cycle_path(production, victim_cycle)
      }.not_to change(AuditionCycle, :count)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "audition schedule/notify (found by UnscopedFind cop)" do
    let!(:victim_cycle) { create(:audition_cycle, production: victim_production) }

    it "404s the schedule page for a foreign cycle through my production id" do
      get manage_schedule_auditions_signups_auditions_cycle_path(production, victim_cycle)
      expect(response).to have_http_status(:not_found)
    end

    it "blocks notify_preview for a foreign cycle" do
      # set_audition_cycle scopes through @production and redirects on a miss,
      # so this is caught before the action body (which is also scoped now).
      get manage_notify_preview_signups_auditions_cycle_path(production, victim_cycle)
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "casting role assignment (found by UnscopedFind cop)" do
    let!(:my_show) { create(:show, production: production, casting_enabled: true) }
    let!(:my_person) { create(:person).tap { |p| org.people << p } }
    let!(:victim_role) { create(:role, production: victim_production) }

    it "404s assigning my person to a foreign org's role" do
      expect {
        post manage_casting_show_assign_person_path(production, my_show),
             params: { person_id: my_person.id, role_id: victim_role.id }
      }.not_to change(ShowPersonRoleAssignment, :count)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "audition requests (C-4)" do
    let!(:victim_cycle) { create(:audition_cycle, production: victim_production) }
    let!(:victim_request) { create(:audition_request, audition_cycle: victim_cycle) }

    it "404s listing a foreign cycle's applicants through my production id" do
      get manage_signups_auditions_cycle_requests_path(production, victim_cycle)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "audition session management (C-5)" do
    let!(:victim_cycle) { create(:audition_cycle, production: victim_production) }
    let!(:victim_session) { create(:audition_session, audition_cycle: victim_cycle) }
    let!(:victim_request) { create(:audition_request, audition_cycle: victim_cycle) }
    let!(:victim_audition) do
      create(:audition, audition_request: victim_request, audition_session: victim_session,
                        auditionable: victim_request.requestable)
    end

    it "404s add_to_session against a foreign session" do
      expect {
        post "/manage/auditions/add_to_session",
             params: { audition_request_id: victim_request.id, audition_session_id: victim_session.id }
      }.not_to change(Audition, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "404s remove_from_session instead of destroying a foreign audition" do
      expect {
        post "/manage/auditions/remove_from_session",
             params: { audition_id: victim_audition.id, audition_session_id: victim_session.id }
      }.not_to change(Audition, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "404s move_to_session against foreign records" do
      other_session = create(:audition_session, audition_cycle: victim_cycle)

      post "/manage/auditions/move_to_session",
           params: { audition_id: victim_audition.id, audition_session_id: other_session.id }

      expect(response).to have_http_status(:not_found)
      expect(victim_audition.reload.audition_session_id).to eq(victim_session.id)
    end
  end

  describe "groups (C-6)" do
    let!(:victim_group) { create(:group).tap { |g| victim_org.groups << g } }

    it "404s on show and destroy of a foreign group" do
      get manage_contacts_group_path(victim_group)
      expect(response).to have_http_status(:not_found)

      expect {
        delete manage_destroy_contacts_group_path(victim_group)
      }.not_to change(Group, :count)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "messages (C-2)" do
    let!(:victim_thread) do
      Message.create!(sender: victim_owner, subject: "Private cast plans", body: "secret",
                      message_type: "direct", visibility: :personal, organization: victim_org)
    end

    it "redirects a non-participant away from a foreign thread" do
      get manage_message_path(victim_thread)

      expect(response).to redirect_to(manage_messages_path)
      follow_redirect!
      expect(response.body).not_to include("Private cast plans")
    end

    it "blocks reactions and poll votes from non-participants" do
      post "/manage/messages/#{victim_thread.id}/react/#{CGI.escape('❤️')}"
      expect(response).to have_http_status(:forbidden)

      post "/manage/messages/#{victim_thread.id}/vote_poll", params: { option_id: 1 }
      expect(response).to redirect_to(manage_messages_path)
    end
  end

  describe "email logs (H-1)" do
    let!(:victim_log) { create(:email_log, organization: victim_org, user: victim_owner) }

    it "404s on a foreign org's email body" do
      get manage_contacts_email_path(victim_log)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "casting availability org_* actions (H-2)" do
    let!(:victim_show) { create(:show, production: victim_production) }
    let!(:victim_person) { create(:person).tap { |p| victim_org.people << p } }

    it "404s the show modal for a foreign show" do
      get manage_org_availability_show_modal_path(victim_show)
      expect(response).to have_http_status(:not_found)
    end

    it "404s casting a person into a foreign show" do
      role = create(:role, production: victim_production)

      expect {
        post manage_org_availability_cast_person_path,
             params: { show_id: victim_show.id, role_id: role.id, person_id: victim_person.id }
      }.not_to change(ShowPersonRoleAssignment, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "404s forging availability on a foreign show" do
      expect {
        post manage_org_availability_set_availability_path,
             params: { show_id: victim_show.id, person_id: victim_person.id, status: "available" }
      }.not_to change(ShowAvailability, :count)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "locations (H-3)" do
    let!(:victim_location) { create(:location, organization: victim_org) }

    it "404s on show/update/destroy of a foreign venue" do
      get manage_location_path(victim_location)
      expect(response).to have_http_status(:not_found)

      patch manage_location_path(victim_location), params: { location: { name: "Hijacked" } }
      expect(response).to have_http_status(:not_found)
      expect(victim_location.reload.name).not_to eq("Hijacked")

      expect { delete manage_location_path(victim_location) }.not_to change(Location, :count)
    end
  end

  describe "sign-up registrations (H-4)" do
    let!(:my_form) { create(:sign_up_form, production: production) }
    let!(:victim_form) { create(:sign_up_form, production: victim_production) }
    let!(:victim_slot) { create(:sign_up_slot, sign_up_form: victim_form) }
    let!(:victim_registration) do
      create(:sign_up_registration, sign_up_slot: victim_slot, person: create(:person), status: "confirmed")
    end

    it "404s cancelling a foreign registration through my own form" do
      delete manage_cancel_registration_signups_form_path(production, my_form, victim_registration)

      expect(response).to have_http_status(:not_found)
      expect(victim_registration.reload.status).to eq("confirmed")
    end
  end

  describe "advance waivers (M-1)" do
    let!(:victim_show) { create(:show, production: victim_production) }
    let!(:victim_waiver) do
      ShowAdvanceWaiver.create!(show: victim_show, person: create(:person), waived_by: victim_owner,
                                reason: "no_advances_this_show")
    end

    it "404s deleting a foreign waiver through my production id" do
      expect {
        delete manage_destroy_money_advance_waiver_path(production, victim_waiver)
      }.not_to change(ShowAdvanceWaiver, :count)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "talent pools via people controller (M-2)" do
    let!(:victim_pool) { create(:talent_pool, production: victim_production) }
    let!(:my_person) { create(:person).tap { |p| org.people << p } }

    it "404s pushing my person into a foreign org's pool" do
      post manage_add_to_cast_contacts_person_path(my_person),
           params: { talent_pool_id: victim_pool.id, person_id: my_person.id }

      expect(response).to have_http_status(:not_found)
      expect(victim_pool.people).not_to include(my_person)
    end
  end

  describe "directory group availability (M-3)" do
    let!(:victim_group) { create(:group).tap { |g| victim_org.groups << g } }

    it "404s writing availability for a foreign group" do
      patch manage_update_group_availability_path(victim_group)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "show payout payees (low)" do
    let!(:my_show) { create(:show, production: production) }
    let!(:my_payout) do
      ShowPayout.create!(show: my_show, status: "awaiting_payout", calculated_at: Time.current, total_payout: 10)
    end
    let!(:victim_person) { create(:person).tap { |p| victim_org.people << p } }

    it "404s naming a foreign person as a payee on my payout" do
      post manage_add_line_item_money_show_payout_path(my_show),
           params: { payee_type: "Person", payee_id: victim_person.id }

      expect(response).to have_http_status(:not_found)
      expect(my_payout.line_items.count).to eq(0)
    end
  end
end
