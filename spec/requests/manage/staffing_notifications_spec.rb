# frozen_string_literal: true

require "rails_helper"

# The staffing notifications list (Staffing settings → Notifications) and the
# can't-make-it alert it powers: chosen managers get an in-app message when a
# staff member declines a shift.
RSpec.describe "Staffing notifications", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:owner_person) { create(:person, user: owner) }

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  describe "the settings section" do
    before { sign_in(owner) }

    it "renders the manager checklist" do
      get manage_staffing_settings_section_path(section: "notifications")
      expect(response.body).to include("Can't-make-it alerts")
      expect(response.body).to include(owner.email_address)
    end

    it "stores the chosen managers" do
      patch manage_staffing_settings_path, params: { updating_notifications: "1", notification_user_ids: [ owner.id ] }
      expect(org.reload.staffing_notification_user_ids).to eq([ owner.id ])

      # An all-unchecked submit clears the list (the marker param routes it).
      patch manage_staffing_settings_path, params: { updating_notifications: "1" }
      expect(org.reload.staffing_notification_user_ids).to eq([])
    end

    it "refuses ids that aren't current managers" do
      outsider = create(:user)
      patch manage_staffing_settings_path, params: { updating_notifications: "1", notification_user_ids: [ outsider.id ] }
      expect(org.reload.staffing_notification_user_ids).to eq([])
    end
  end

  describe "declining a shift" do
    let(:worker_user) { create(:user, password: password) }
    let(:worker) { create(:person, user: worker_user, name: "Sam Staffer") }
    let(:role) { create(:house_role, organization: org, name: "Bartender") }
    let(:shift) { create(:shift, organization: org, house_role: role) }
    let!(:assignment) { create(:shift_assignment, shift: shift, person: worker) }

    before do
      org.update!(staffing_notification_user_ids: [ owner.id ])
      sign_in(worker_user)
    end

    it "enqueues the manager alert with the decline" do
      expect {
        post my_decline_shift_path(assignment), params: { reason: "Family thing" }
      }.to change { ActiveJob::Base.queue_adapter.enqueued_jobs.count { |j| j["job_class"] == "ShiftDeclinedNotificationJob" } }.by(1)

      expect(assignment.reload).to be_declined
    end
  end
end
