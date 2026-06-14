# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::Auditions schedule (click-to-add)", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:production) { create(:production, organization: org) }
  let(:cycle) { create(:audition_cycle, production: production) }
  let(:location) { create(:location, organization: org) }
  let!(:session) { create(:audition_session, audition_cycle: cycle, location: location) }

  let(:available_person) { create(:person, name: "Ava Available") }
  let(:other_person) { create(:person, name: "Ned NoResponse") }
  let!(:req_available) { create(:audition_request, audition_cycle: cycle, requestable: available_person) }
  let!(:req_other) { create(:audition_request, audition_cycle: cycle, requestable: other_person) }

  before do
    AuditionSessionAvailability.create!(available_entity: available_person, audition_session: session, status: :available)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  describe "GET schedule_auditions" do
    it "renders the click-to-add UI with both auditionees and the availability payload" do
      get manage_schedule_auditions_signups_auditions_cycle_path(production, cycle)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Schedule Auditions")
      expect(response.body).to include("audition-assign")
      expect(response.body).to include("Review &amp; notify") # finalize/notify entry point
      expect(response.body).to include("Ava Available")
      # The session's add slot + availability are embedded for the modal.
      expect(response.body).to include("data-add-slot")
      expect(response.body).to include("audition-assign#slotsClick")
      payload = response.body[/data-audition-assign-payload-value="([^"]*)"/, 1]
      data = JSON.parse(CGI.unescapeHTML(payload))
      expect(data["availability"][session.id.to_s][req_available.id.to_s]).to eq("available")
    end
  end

  describe "POST add_to_session (ui: v2)" do
    it "creates an Audition and returns the refreshed session slots only" do
      expect {
        post "/manage/auditions/add_to_session",
             params: { audition_request_id: req_available.id, audition_session_id: session.id, ui: "v2" }
      }.to change(Audition, :count).by(1)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["session_id"]).to eq(session.id)
      expect(body["session_slots_html"]).to include("Ava Available")
      expect(body["scheduled_request_ids"]).to include(req_available.id)
      # The lightweight path skips the heavy legacy partials.
      expect(body).not_to have_key("right_list_html")
      expect(body).not_to have_key("sessions_list_html")
    end

    it "does not duplicate an already-scheduled auditionee in the same session" do
      create(:audition, audition_request: req_available, audition_session: session, auditionable: available_person)
      expect {
        post "/manage/auditions/add_to_session",
             params: { audition_request_id: req_available.id, audition_session_id: session.id, ui: "v2" }
      }.not_to change(Audition, :count)
    end
  end

  describe "POST remove_from_session (ui: v2)" do
    it "removes the Audition and returns refreshed slots" do
      audition = create(:audition, audition_request: req_available, audition_session: session, auditionable: available_person)

      expect {
        post "/manage/auditions/remove_from_session",
             params: { audition_id: audition.id, audition_session_id: session.id, ui: "v2" }
      }.to change(Audition, :count).by(-1)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["session_id"]).to eq(session.id)
      expect(body["session_slots_html"]).not_to include("Ava Available")
    end
  end

  describe "GET notify_preview" do
    it "splits auditionees into invited (scheduled) and not-invited" do
      # Schedule the available person; leave the other unscheduled.
      create(:audition, audition_request: req_available, audition_session: session, auditionable: available_person)

      get manage_notify_preview_signups_auditions_cycle_path(production, cycle)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)

      expect(body["invited_count"]).to eq(1)
      expect(body["not_invited_count"]).to eq(1)
      expect(body["invited"].first["name"]).to eq("Ava Available")
      expect(body["invited"].first["sessions"]).to be_present
      expect(body["not_invited"].first["name"]).to eq("Ned NoResponse")
    end
  end

  describe "POST finalize_and_notify_invitations with edited messages" do
    before do
      create(:audition, audition_request: req_available, audition_session: session, auditionable: available_person)
      # Give both auditionees accounts so they can receive in-app messages.
      available_person.update!(user: create(:user))
      other_person.update!(user: create(:user))
    end

    it "sends invited + not-invited messages, appends session time, and finalizes" do
      expect {
        post manage_finalize_and_notify_invitations_signups_auditions_cycle_path(production, cycle),
             params: { invited_body: "Hi [Name], you're in!", not_invited_body: "Hi [Name], not this time." }
      }.to change(Message, :count).by(2)

      cycle.reload
      expect(cycle.finalize_audition_invitations).to be(true)

      invited_msg = Message.joins(:message_recipients)
                           .where(message_recipients: { recipient: available_person }).last
      expect(invited_msg.body.to_plain_text).to include("you're in!")
      expect(invited_msg.body.to_plain_text).to include("Ava Available")     # [Name] replaced
      expect(invited_msg.body.to_plain_text).to include("Your audition time") # session appended

      not_invited_msg = Message.joins(:message_recipients)
                               .where(message_recipients: { recipient: other_person }).last
      expect(not_invited_msg.body.to_plain_text).to include("not this time")
      expect(not_invited_msg.body.to_plain_text).to include("Ned NoResponse")
    end
  end

  describe "legacy drag endpoints still respond (other pages)" do
    it "returns the legacy partials when ui is not v2" do
      post "/manage/auditions/add_to_session",
           params: { audition_request_id: req_available.id, audition_session_id: session.id }
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to have_key("right_list_html")
      expect(body).to have_key("sessions_list_html")
    end
  end
end
