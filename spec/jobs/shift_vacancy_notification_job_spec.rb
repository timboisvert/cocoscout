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

  it "says put on, not covering, when a manager assigned by hand, and 'you' to the one who dropped it" do
    vacancy.fill!(priya)
    expect { described_class.perform_now(vacancy.id, "filled") }.to change(Notification, :count).by(2)
    to_manager = Notification.find_by(user: manager_user)
    expect(to_manager.title).to eq("Priya Kaur has been put on the Bar shift on #{shift.starts_at.strftime('%a, %b %-d')}")
    expect(to_manager.body).to include("that Dana Morris couldn't make, and will be notified")
    expect(to_manager.body).not_to include("is covering")
    to_dana = Notification.find_by(user: dana_user)
    expect(to_dana.body).to include("that you couldn't make")
    expect(to_dana.body).not_to include("Dana Morris couldn't")
  end

  it "says they've been notified once a hand assignment notified them" do
    vacancy.fill!(priya)
    shift.shift_assignments.find_by(person: priya).update!(notified_at: Time.current)
    described_class.perform_now(vacancy.id, "filled")
    expect(Notification.find_by(user: manager_user).body).to include("couldn't make, and has been notified.")
  end

  it "never says someone with no login will be told" do
    priya.update!(user: nil)
    vacancy.fill!(priya)
    described_class.perform_now(vacancy.id, "filled")
    body = Notification.find_by(user: manager_user).body
    expect(body).to include("that Dana Morris couldn't make.")
    expect(body).not_to include("notified")
  end

  # Tim, 2026-11-10: the others asked hear it's gone, by notification only.
  it "notifies the others asked who hadn't answered that it's covered, and nobody else" do
    lee = create(:person, name: "Lee Chen", user: create(:user))
    sam = create(:person, name: "Sam Oduya", user: create(:user))
    nolan = create(:person, name: "Nolan Nologin")
    [ priya, lee, sam, nolan ].each { |person| vacancy.invitations.create!(person: person, email_subject: "s", email_body: "b") }
    vacancy.invitations.find_by(person: sam).decline!
    vacancy.invitations.find_by(person: priya).claim!

    expect { described_class.perform_now(vacancy.id, "filled") }.not_to have_enqueued_mail(StaffingNoticeMailer, :notice).with(lee, any_args)
    to_lee = Notification.find_by(user: lee.user)
    expect(to_lee.kind).to eq("shift_vacancy_covered_invitee")
    expect(to_lee.title).to eq("The Bar shift on #{shift.starts_at.strftime('%a, %b %-d')} has been covered")
    expect(to_lee.body).to include("Hi Lee", "has been covered and is no longer available")
    expect(Notification.where(user: [ sam.user, priya.user ]).where(kind: "shift_vacancy_covered_invitee")).to be_empty
  end

  it "says nothing to the others asked once the shift is over" do
    lee = create(:person, name: "Lee Chen", user: create(:user))
    vacancy.invitations.create!(person: lee, email_subject: "s", email_body: "b")
    vacancy.fill!(priya)
    shift.update_columns(starts_at: 5.hours.ago, ends_at: 1.hour.ago)
    described_class.perform_now(vacancy.id, "filled")
    expect(Notification.where(user: lee.user)).to be_empty
  end

  it "names the whole role label" do
    shift.assign_additional_roles!([ create(:house_role, organization: org, name: "Door").id ])
    vacancy.fill!(priya, accepted: true)
    described_class.perform_now(vacancy.id, "filled")
    expect(Notification.find_by(user: dana_user).body).to include("Bar + Door")
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
