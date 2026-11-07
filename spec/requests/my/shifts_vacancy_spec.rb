# frozen_string_literal: true

require "rails_helper"

# The staffer's side of a shift they can't make (the performer flow, for
# staff): the sheet, the row by where it stands, taking it back while it's
# open, the settled row once someone has it, and the invitation to cover
# someone else's shift on My Shifts and My Calendar.
RSpec.describe "My::Shifts can't make it", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user, name: "Dana Morris") }
  let!(:org) { create(:organization, :pro, name: "Stars & Garters") }
  let!(:membership) { create(:organization_staff_member, organization: org, person: person) }
  let!(:role) { create(:house_role, organization: org, name: "Bar") }
  let(:shift_at) { 1.week.from_now.change(hour: 19) }
  let!(:shift) { create(:shift, organization: org, house_role: role, starts_at: shift_at, ends_at: shift_at + 4.hours) }
  let!(:assignment) { shift.shift_assignments.create!(person: person, position: 1, notified_at: 1.day.ago) }
  let(:priya) { create(:person, name: "Priya Kaur") }

  before do
    org.people << person
    StaffingFinalization.create!(organization: org, week_start: shift_at.to_date.beginning_of_week, finalized_at: Time.current)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  it "offers the sheet, and the row says they've been told once you can't make it" do
    get my_shifts_path
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    sheet = doc.at_css("#cant-make-it-#{assignment.id}[data-sheet]")
    expect(sheet).to be_present
    expect(sheet.text).to include("Can't make this shift?", "Bar", "so they can sort out cover")
    expect(sheet.at_css("button[type='submit'][form='decline-shift-#{assignment.id}']")).to be_present

    post my_decline_shift_path(assignment), params: { reason: "Out of town" }
    expect(response).to redirect_to(my_shifts_path)
    vacancy = assignment.reload.active_vacancy
    expect(vacancy).to be_present

    get my_shifts_path
    row = Nokogiri::HTML(response.body).at_css("[data-shift-row='dropped']")
    expect(row.text).to include("You told them you can't make it", "Out of town", "I'm back on")
    expect(row.text).not_to include("finding someone")

    vacancy.invitations.create!(person: priya)
    vacancy.mark_finding_replacement!
    get my_shifts_path
    expect(Nokogiri::HTML(response.body).at_css("[data-shift-state]").text).to include("they're finding someone to cover it")
  end

  it "takes it back while it's open, through the vacancy" do
    assignment.decline!
    vacancy = assignment.active_vacancy
    post my_undo_decline_shift_path(assignment)
    expect(response).to redirect_to(my_shifts_path)
    expect(assignment.reload).not_to be_declined
    expect(vacancy.reload).to be_cancelled
  end

  it "shows who has it once someone covers it, with nothing to press" do
    assignment.decline!
    assignment.active_vacancy.fill!(priya, accepted: true)
    get my_shifts_path
    doc = Nokogiri::HTML(response.body)
    row = doc.at_css("[data-shift-row='settled']")
    expect(row.text).to include("Bar", "Priya Kaur has it now")
    expect(row.at_css("form")).to be_nil
    expect(doc.at_css("[data-shift-row='dropped']")).to be_nil

    post my_undo_decline_shift_path(assignment)
    expect(response).to redirect_to(my_shifts_path)
    expect(flash[:alert]).to include("couldn't find that shift")
  end

  it "says they're not filling it" do
    assignment.decline!
    assignment.active_vacancy.mark_not_filling!
    get my_shifts_path
    expect(Nokogiri::HTML(response.body).at_css("[data-shift-outcome]").text).to include("They're not filling it")
  end

  it "refuses a decline on a shift that's over" do
    shift.update!(starts_at: 2.days.ago, ends_at: 2.days.ago + 4.hours)
    post my_decline_shift_path(assignment)
    expect(flash[:alert]).to include("already over")
    expect(assignment.reload).not_to be_declined
  end

  it "shows an invitation to cover someone else's shift on My Shifts and My Calendar" do
    other = create(:person, name: "Lee Chen")
    other_shift = create(:shift, organization: org, house_role: role, starts_at: shift_at + 1.day, ends_at: shift_at + 1.day + 4.hours)
    dropped = other_shift.shift_assignments.create!(person: other, position: 1).tap(&:decline!)
    invitation = dropped.active_vacancy.invitations.create!(person: person)

    get my_shifts_path
    panel = Nokogiri::HTML(response.body).at_css("[data-alert-panel]")
    expect(panel.text).to include("You're invited to cover a shift", "Bar", "Stars & Garters", "Claim shift", "Decline")
    expect(panel.at_css("a[href='#{claim_shift_path(invitation.token)}']")).to be_present

    get my_dashboard_path
    home = Nokogiri::HTML(response.body)
    expect(home.css("[data-alert-panel]").map(&:text).join).to include("You're invited to cover a shift")
    expect(home.at_css("a[href='#{claim_shift_path(invitation.token)}']")).to be_present

    invitation.claim!
    get my_shifts_path
    expect(Nokogiri::HTML(response.body).text).not_to include("You're invited to cover a shift")
  end
end
