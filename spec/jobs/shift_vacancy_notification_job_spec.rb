# frozen_string_literal: true

require "rails_helper"

# A shift vacancy covered or taken back: the chosen managers hear, and
# whoever dropped it hears who's covering it, as Notifications in the Shifts
# group with no person attributed.
RSpec.describe ShiftVacancyNotificationJob, type: :job do
  let(:org) { create(:organization, owner: create(:user)) }
  let(:manager_user) { create(:user) }
  let!(:manager_person) { create(:person, user: manager_user) }
  let!(:manager_role) { create(:organization_role, :manager, user: manager_user, organization: org) }
  let(:role) { create(:house_role, organization: org, name: "Bar") }
  let(:shift) { create(:shift, organization: org, house_role: role) }
  let(:dana_user) { create(:user) }
  let(:dana) { create(:person, name: "Dana Morris", user: dana_user) }
  let(:priya) { create(:person, name: "Priya Kaur", user: create(:user)) }
  let(:assignment) { shift.shift_assignments.create!(person: dana, position: 1) }

  before do
    org.update!(staffing_notification_user_ids: [ manager_user.id ])
    assignment.decline!(reason: "Sick")
  end

  let(:vacancy) { assignment.active_vacancy }

  it "tells the managers and the one who dropped it who's covering it" do
    vacancy.fill!(priya, accepted: true)

    expect { described_class.perform_now(vacancy.id, "filled") }.to change(Notification, :count).by(2)

    to_manager = Notification.find_by(user: manager_user)
    expect(to_manager.category).to eq("shifts")
    expect(to_manager.body).to include("Priya Kaur", "Bar", "Dana Morris")
    expect(to_manager.path).to include("/manage/staffing/vacancies/#{vacancy.id}")

    to_dana = Notification.find_by(user: dana_user)
    expect(to_dana.body).to include("Priya Kaur is covering")
    expect(to_dana.path).to include("/my/shifts")
    expect(Message.count).to eq(0)
  end

  it "tells the managers they're back on" do
    vacancy.reclaim!

    expect { described_class.perform_now(vacancy.id, "reclaimed") }.to change(Notification, :count).by(1)
    expect(Notification.last.user).to eq(manager_user)
    expect(Notification.last.body).to include("Dana Morris", "back on")
  end

  it "no-ops for a vacancy that isn't filled when a filled event arrives" do
    expect { described_class.perform_now(vacancy.id, "filled") }.not_to change(Notification, :count)
  end
end
