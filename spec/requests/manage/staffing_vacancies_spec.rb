# frozen_string_literal: true

require "rails_helper"

# A shift someone can't make, the performer flow's way: the manager's page
# shows who dropped it, picks who to ask through the People Picker's staff
# scope (free people first; the dropper, the invited and whoever's on it
# marked), sends each an invitation with a claim link, and can assign by
# hand, not fill it, or put the person back. Links to it from Scheduling.
RSpec.describe "Manage::Staffing shift vacancies", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:bar) { create(:house_role, organization: org, name: "Bar") }
  let(:shift_at) { 1.week.from_now.change(hour: 19, min: 0) }
  let!(:shift) { create(:shift, organization: org, house_role: bar, required_count: 2, starts_at: shift_at, ends_at: shift_at + 4.hours) }

  def staff!(name)
    person = create(:person, name: name, user: create(:user))
    org.people << person
    member = create(:organization_staff_member, organization: org, person: person)
    create(:staff_role_qualification, organization_staff_member: member, house_role: bar)
    person
  end

  let!(:dana) { staff!("Dana Morris") }
  let!(:priya) { staff!("Priya Kaur") }
  let!(:lee) { staff!("Lee Chen") }
  let!(:marco) { staff!("Marco Ruiz") }
  let!(:sam) { staff!("Sam Oduya") }
  let!(:assignment) { shift.shift_assignments.create!(person: dana, position: 1, notified_at: 1.day.ago) }
  let!(:marco_row) { shift.shift_assignments.create!(person: marco, position: 2, notified_at: 1.day.ago) }

  before do
    assignment.decline!(reason: "Out of town")
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  let(:vacancy) { assignment.active_vacancy }

  it "shows the shift, who dropped it, and who to ask, with Send pinned" do
    get manage_staffing_vacancy_path(vacancy)
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    expect(response.body).to include("Shift to cover", "Dana Morris", "Out of town", "Marco Ruiz")

    picker = doc.at_css("[data-people-picker='vacancy-picker']")
    params = JSON.parse(picker["data-people-picker-params-value"])
    expect(params).to include("scope" => "staff", "shift_id" => shift.id, "exclude_label" => "Can't make it")
    expect(params["exclude"]).to eq([ "Person_#{dana.id}" ])
    expect(picker["data-people-picker-multi-value"]).to eq("true")

    add_all = doc.at_css("[data-vacancy-invitees] [data-action='click->invite-picks#addAll']")
    expect(JSON.parse(add_all["data-members"]).map { |m| m["name"] }).to contain_exactly("Priya Kaur", "Lee Chen", "Sam Oduya")
    expect(doc.at_css("[data-sticky-actions]").text).to include("Send invitations")
    expect(response.body).to include("Not filling it", "Put Dana back", "Assign someone directly")

    # The picker's list: the dropper, the one on it and the free ones marked.
    get manage_people_picker_search_path(params), headers: { "X-Requested-With" => "XMLHttpRequest" }
    body = response.body
    expect(body).to include("Priya Kaur", "Lee Chen", "Can&#39;t make it", "Assigned")
    expect(body.index("Priya Kaur")).to be < body.index("Dana Morris")
    expect(body.index("Lee Chen")).to be < body.index("Marco Ruiz")
  end

  it "sends the manager's words to the chosen people, each with their own claim link" do
    expect {
      post manage_send_invitations_staffing_vacancy_path(vacancy), params: {
        member_ids: [ "Person_#{priya.id}", "Person_#{lee.id}", "Person_#{dana.id}", "Person_#{marco.id}" ],
        email_draft: { title: "Cover {{role_name}} on {{shift_date}}?", body: "<p>Hi {{recipient_name}}, we need you. <a href=\"{{claim_url}}\">Claim</a></p>" }
      }
    }.to change(ShiftVacancyInvitation, :count).by(2)
    expect(response).to redirect_to(manage_staffing_vacancy_path(vacancy))
    expect(vacancy.reload).to be_finding_replacement
    invitation = vacancy.invitations.find_by(person: priya)
    expect(invitation.email_subject).to eq("Cover Bar on #{shift_at.strftime('%a, %b %-d')}?")
    expect(invitation.email_body).to include("{{recipient_name}}", "{{claim_url}}")
    expect(enqueued_jobs.count { |j| j["job_class"] == "ActionMailer::MailDeliveryJob" && j["arguments"].first == "ShiftVacancyInvitationMailer" }).to eq(2)

    get manage_staffing_vacancy_path(vacancy)
    expect(response.body).to include("Asked so far", "Unanswered", "Ask more people")
    doc = Nokogiri::HTML(response.body)
    params = JSON.parse(doc.at_css("[data-people-picker='vacancy-picker']")["data-people-picker-params-value"])
    expect(params["invited"]).to contain_exactly(priya.id, lee.id)
  end

  it "asks for someone when nobody was chosen" do
    post manage_send_invitations_staffing_vacancy_path(vacancy), params: { member_ids: [] }
    expect(response).to redirect_to(manage_staffing_vacancy_path(vacancy))
    expect(flash[:alert]).to include("Choose at least one person")
  end

  it "counts a hand assignment as cover and says so" do
    post manage_assign_staffing_shift_path(shift), params: { person_id: priya.id },
         headers: { "HTTP_REFERER" => manage_staffing_vacancy_url(vacancy) }
    expect(response).to redirect_to(manage_staffing_vacancy_url(vacancy))
    expect(flash[:notice]).to include("Assigned Priya Kaur.", "covers the shift Dana Morris couldn't make")
    expect(vacancy.reload).to be_filled
    expect(shift.shift_assignments.reload.map(&:person)).to contain_exactly(marco, priya)

    get manage_staffing_vacancy_path(vacancy)
    expect(response.body).to include("Covered", "Priya Kaur", "Dana Morris's row is gone", "Notify updates")
    expect(response.body).not_to include("Send invitations")
  end

  it "closes the hole on Not filling it, and puts the person back on Put back" do
    post manage_cancel_staffing_vacancy_path(vacancy)
    expect(response).to redirect_to(manage_staffing_scheduling_path(day: shift_at.to_date.iso8601))
    expect(vacancy.reload).to be_not_filling
    expect(shift.shift_assignments.reload.map(&:person)).to eq([ marco ])
    get manage_staffing_vacancy_path(vacancy)
    expect(response.body).to include("Not filling it")

    second = shift.shift_assignments.create!(person: lee, position: 3).tap { |a| a.decline!(reason: "Sick") }
    other = second.active_vacancy
    post manage_reclaim_staffing_vacancy_path(other)
    expect(response).to redirect_to(manage_staffing_scheduling_path(day: shift_at.to_date.iso8601))
    expect(other.reload).to be_cancelled
    expect(second.reload).not_to be_declined
  end

  it "removing the one who dropped it closes the vacancy quietly" do
    open_vacancy = vacancy
    delete manage_unassign_staffing_shift_path(shift, person_id: dana.id)
    expect(open_vacancy.reload).to be_cancelled
    expect(enqueued_jobs.none? { |j| j["job_class"] == "ShiftVacancyNotificationJob" }).to be(true)
  end

  it "links to the page from Scheduling's can't-make-it sheet and the staffing home" do
    get manage_staffing_scheduling_path(week_start: shift_at.to_date.beginning_of_week.to_s)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(manage_staffing_vacancy_path(vacancy), "Find cover")

    get manage_staffing_index_path
    expect(response.body).to include(manage_staffing_vacancy_path(vacancy))
  end

  it "is scoped to the organization" do
    other_org = create(:organization, owner: create(:user))
    other_shift = create(:shift, organization: other_org, house_role: create(:house_role, organization: other_org))
    stranger = create(:person)
    other = other_shift.shift_assignments.create!(person: stranger, position: 1).tap { |a| a.decline! }.active_vacancy
    get manage_staffing_vacancy_path(other)
    expect(response).to have_http_status(:not_found)
  end
end
