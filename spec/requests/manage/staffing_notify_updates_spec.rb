# frozen_string_literal: true

require "rails_helper"

# Someone who said "I can't make it" keeps their row (the manager has to see
# who dropped and why), but they're off the shift: the week's status bar must
# not count them as an update to send, and a re-notify must not send them the
# shift they declined.
RSpec.describe "Manage::Staffing updates after a decline", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:bar) { create(:house_role, organization: org, name: "Bar") }

  let(:shift_at) { Time.zone.local(2026, 9, 19, 19, 0) }
  let(:week_start) { shift_at.to_date.beginning_of_week }
  let!(:shift) { create(:shift, organization: org, house_role: bar, required_count: 2, starts_at: shift_at, ends_at: shift_at + 4.hours) }

  let(:quinn) { create(:person, name: "Quinn Dropper", user: create(:user)) }
  let(:rae) { create(:person, name: "Rae Steady", user: create(:user)) }
  # Told when the shift was last saved, so neither reads as "changed" until it is edited again.
  let!(:quinns) { shift.shift_assignments.create!(person: quinn, position: 1, notified_at: shift.updated_at) }
  let!(:raes) { shift.shift_assignments.create!(person: rae, position: 2, notified_at: shift.updated_at) }

  before do
    create(:staffing_finalization, organization: org, week_start: week_start)
    quinns.decline!(reason: "Out of town")
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "counts only the people still on the shift as updates to send" do
    get manage_staffing_scheduling_path(week_start: week_start.to_s)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Quinn Dropper") # still shown as the one who can't make it
    expect(response.body).not_to include("update to send")

    # The manager edits the shift: Rae has a change to hear about, Quinn doesn't.
    shift.update!(ends_at: shift_at + 5.hours)
    get manage_staffing_scheduling_path(week_start: week_start.to_s)
    chips = Nokogiri::HTML(response.body).css("[data-update-chip]").map { |c| c.text.squish }
    expect(response.body).to include("1 update to send")
    expect(chips.join(" ")).to include("Rae")
    expect(chips.join(" ")).not_to include("Quinn")
  end

  it "never re-sends the declined shift to the person who dropped it" do
    expect {
      post manage_finalize_staffing_path(week_start: week_start.to_s, notify_all: 1)
    }.to change { Notification.where(user: rae.user).count }.by(1)
       .and change { Notification.where(user: quinn.user).count }.by(0)
  end
end
