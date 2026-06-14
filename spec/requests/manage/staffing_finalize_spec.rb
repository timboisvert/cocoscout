# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::Staffing finalize & staff visibility", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }

  # Next week, so every shift in it is in the future (the My::Shifts page only
  # lists upcoming shifts).
  let(:week_start) { Date.current.beginning_of_week + 7 }
  let(:role) { create(:house_role, organization: org) }

  let(:staff_user) { create(:user, password: password) }
  let(:staff_person) { create(:person, name: "Sam Staff", user: staff_user) }
  let!(:shift) do
    create(:shift, organization: org, house_role: role,
                   starts_at: (week_start + 2).in_time_zone.change(hour: 18),
                   ends_at:   (week_start + 2).in_time_zone.change(hour: 23))
  end
  let!(:assignment) { create(:shift_assignment, shift: shift, person: staff_person) }

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  describe "POST finalize" do
    before { sign_in(owner) }

    it "records the finalization and messages the assigned staffer" do
      expect {
        post manage_finalize_staffing_path(week_start: week_start.to_s)
      }.to change(StaffingFinalization, :count).by(1)
        .and change(Message, :count).by(1)

      fin = StaffingFinalization.last
      expect(fin.organization).to eq(org)
      expect(fin.week_start).to eq(week_start)
      expect(fin.finalized_at).to be_present
      expect(assignment.reload.notified_at).to be_present

      message = Message.last
      expect(message.message_recipients.map(&:recipient)).to include(staff_person)
      # Sent from the system, not the manager who clicked finalize.
      expect(message.sender).to be_nil
      expect(message).to be_system_generated
      expect(message.sender_name).to eq("Automated Notification")
    end

    it "uses the manager's edited subject and message" do
      post manage_finalize_staffing_path(week_start: week_start.to_s),
           params: { subject: "Roster is up!", message: "Here's where you're working." }

      message = Message.last
      expect(message.subject).to eq("Roster is up!")
      expect(message.body.to_plain_text).to include("Here's where you're working.")
      expect(message.body.to_plain_text).to include(role.name) # per-person shift list still appended
    end

    it "re-notifies without creating a duplicate finalization row" do
      post manage_finalize_staffing_path(week_start: week_start.to_s)
      expect {
        post manage_finalize_staffing_path(week_start: week_start.to_s)
      }.to change(Message, :count).by(1)
        .and change(StaffingFinalization, :count).by(0)
    end
  end

  describe "staff visibility (My::Shifts)" do
    before { sign_in(staff_user) }

    it "hides shifts in an unfinalized (draft) week" do
      get my_shifts_path
      expect(response).to have_http_status(:ok)
      # The role name only renders when a shift row is shown.
      expect(response.body).not_to include(role.name)
    end

    it "shows shifts once the week is finalized" do
      create(:staffing_finalization, organization: org, week_start: week_start, finalized_at: Time.current)

      get my_shifts_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(role.name)
    end
  end

  describe "/my home calendar visibility" do
    before { sign_in(staff_user) }

    it "hides draft shifts from the dashboard calendar" do
      get my_dashboard_path(scope: "my_assignments")
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(role.name)
    end

    it "shows shifts on the dashboard calendar once finalized" do
      create(:staffing_finalization, organization: org, week_start: week_start, finalized_at: Time.current)
      get my_dashboard_path(scope: "my_assignments")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(role.name)
    end
  end
end
