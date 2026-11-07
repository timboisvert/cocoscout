# frozen_string_literal: true

require "rails_helper"

# The claim page a shift cover invitation links to: no login, the shift and
# who's on it, their own clashes as warnings; first to claim gets it.
RSpec.describe "Claiming a shift someone can't make", type: :request do
  include ActiveJob::TestHelper

  let(:org) { create(:organization, owner: create(:user), name: "Stars & Garters") }
  let(:bar) { create(:house_role, organization: org, name: "Bar") }
  let(:shift_at) { 1.week.from_now.change(hour: 19) }
  let!(:shift) { create(:shift, organization: org, house_role: bar, required_count: 2, starts_at: shift_at, ends_at: shift_at + 4.hours) }
  let(:dana) { create(:person, name: "Dana Morris", user: create(:user)) }
  let(:priya) { create(:person, name: "Priya Kaur", user: create(:user)) }
  let(:lee) { create(:person, name: "Lee Chen", user: create(:user)) }
  let!(:marco_row) { shift.shift_assignments.create!(person: create(:person, name: "Marco Ruiz"), position: 2) }
  let!(:assignment) { shift.shift_assignments.create!(person: dana, position: 1).tap { |a| a.decline!(reason: "Sick") } }
  let(:vacancy) { assignment.active_vacancy }
  let!(:priya_invitation) { vacancy.invitations.create!(person: priya) }
  let!(:lee_invitation) { vacancy.invitations.create!(person: lee) }

  before { vacancy.mark_finding_replacement! }

  it "shows the shift and Claim / Decline, logged out, and never who else is on it" do
    get claim_shift_path(priya_invitation.token)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Stars &amp; Garters", "Bar", "Claim this shift", "Decline")
    expect(response.body).to include("data-claim-state=\"open\"")
    # Staff aren't shown each other's shifts (Tim, 2026-11-07): not the
    # person who dropped it, not the people still on it.
    expect(response.body).not_to include("Dana Morris", "Marco Ruiz", "Also on this shift")
  end

  it "warns about their own clash without refusing" do
    other = create(:shift, organization: org, house_role: create(:house_role, organization: org, name: "Box office"),
                           starts_at: shift_at - 1.hour, ends_at: shift_at + 1.hour)
    other.shift_assignments.create!(person: priya, position: 1)
    get claim_shift_path(priya_invitation.token)
    expect(response.body).to include("data-claim-warnings", "Box office", "Claim this shift")
  end

  it "gives the shift to the first to claim; the second finds it taken" do
    post do_claim_shift_path(priya_invitation.token)
    expect(response).to redirect_to(claim_shift_success_path(priya_invitation.token))
    follow_redirect!
    expect(response.body).to include("You're on it")
    expect(shift.shift_assignments.reload.map { |a| a.person.name }).to contain_exactly("Marco Ruiz", "Priya Kaur")
    expect(shift.shift_assignments.find_by(person: priya)).to have_attributes(accepted_at: be_present, notified_at: be_present)
    expect(vacancy.reload).to be_filled
    expect(enqueued_jobs.map { |j| [ j["job_class"], j["arguments"] ] }).to include([ "ShiftVacancyNotificationJob", [ vacancy.id, "filled" ] ])
    # Their own confirmation, with the shift in it, the moment they claim.
    expect(enqueued_jobs.map { |j| [ j["job_class"], j["arguments"] ] }).to include([ "ShiftVacancyNotificationJob", [ vacancy.id, "claimed", priya_invitation.id ] ])
    expect { perform_enqueued_jobs(only: ShiftVacancyNotificationJob) }.to change { priya.user.notifications.count }.by(1)
    confirmation = priya.user.notifications.order(:id).last
    expect(confirmation.kind).to eq("shift_claim_confirmed")
    expect(confirmation.title).to eq("You've got the Bar shift, #{shift_at.strftime('%a %b %-d')}: 7:00–11:00 PM")
    expect(confirmation.body).to include("Thanks for covering for Dana Morris")
    expect(confirmation.path).to eq("/my/shifts#shift-#{shift.id}")

    post do_claim_shift_path(lee_invitation.token)
    expect(response).to redirect_to(claim_shift_path(lee_invitation.token))
    follow_redirect!
    expect(response.body).to include("data-claim-state=\"gone\"", "Someone else has this shift now")

    get claim_shift_path(priya_invitation.token)
    expect(response.body).to include("data-claim-state=\"claimed\"")
  end

  it "takes a decline, and still lets them claim while it's open" do
    post decline_claim_shift_path(priya_invitation.token)
    expect(response).to redirect_to(claim_shift_path(priya_invitation.token))
    expect(priya_invitation.reload).to be_declined
    get claim_shift_path(priya_invitation.token)
    expect(response.body).to include("You declined, but you can still claim it", "Claim this shift")
  end

  # Tim, 2026-11-07: claim invitations go away when the show happens.
  it "says the shift has already happened once it is over, and takes no claim" do
    travel_to(shift.ends_at + 1.day) do
      get claim_shift_path(priya_invitation.token)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-claim-state=\"gone\"", "This shift has already happened")
      expect(response.body).not_to include("Claim this shift")

      post do_claim_shift_path(priya_invitation.token)
      expect(response).to redirect_to(claim_shift_path(priya_invitation.token))
      expect(vacancy.reload).to be_finding_replacement
      expect(shift.shift_assignments.active.where(person: priya)).not_to exist
    end
  end

  it "sends a bad token home" do
    get claim_shift_path("nope")
    expect(response).to redirect_to(root_path)
  end
end
