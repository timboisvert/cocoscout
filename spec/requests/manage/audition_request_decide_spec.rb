# frozen_string_literal: true

require "rails_helper"

# A cycle with no audition sessions (video-only, or open-ended and never set
# up) decides each sign-up on its own page: add to the talent pool, or not
# this time, with the email shown first (Tim, 2026-11-17). The casting board
# lists those cycles' sign-ups too, and its Finalize & notify sends the words
# the manager edited.
RSpec.describe "Deciding an audition request on its own page", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:production) { create(:production, organization: org, name: "Night Owls") }
  let(:cycle) { create(:audition_cycle, production: production, active: true) } # in person, no sessions
  let(:person) { create(:person, name: "Wren Ward", user: create(:user)).tap { |p| org.people << p } }
  let!(:audition_request) { create(:audition_request, audition_cycle: cycle, requestable: person) }
  let(:pool) { production.effective_talent_pool }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def show_page
    get manage_signups_auditions_cycle_request_path(production, cycle, audition_request)
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body)
  end

  def decide(decision, subject: "Night Owls news", body: "<div>Hello [Name], it's settled.</div>")
    post manage_decide_signups_auditions_cycle_request_path(production, cycle, audition_request),
         params: { decision: decision, subject: subject, body: body }
  end

  it "counts a cycle with no sessions, or a video-only one, as decided from its requests" do
    expect(cycle.decided_from_requests?).to be(true)
    create(:audition_session, audition_cycle: cycle)
    expect(cycle.reload.decided_from_requests?).to be(false)
    expect(build(:audition_cycle, :video_upload, production: production).decided_from_requests?).to be(true)
  end

  it "offers both decisions, each with this person's email ready to read and change" do
    doc = show_page
    expect(doc.at_css("button[data-modal-id='decide-cast-#{audition_request.id}']").text).to include("Add to talent pool")
    expect(doc.at_css("button[data-modal-id='decide-rejected-#{audition_request.id}']").text).to include("Not this time")

    modal = doc.at_css("#decide-cast-#{audition_request.id}")
    expect(modal.at_css("h3").text).to eq("Add Wren to the talent pool?")
    draft = ContentTemplateService.render("audition_added_to_cast",
                                          { recipient_name: "Wren", production_name: "Night Owls", talent_pool_name: pool.name })
    expect(modal.at_css("input[name='subject']")["value"]).to eq(draft[:subject])
    expect(modal.at_css("input[type='hidden'][name='body']")["value"]).to eq(draft[:body])
    expect(modal.at_css("form")["action"]).to eq(manage_decide_signups_auditions_cycle_request_path(production, cycle, audition_request))
  end

  it "adds them to the talent pool, sends the words as edited, and records a notified decision" do
    expect { decide("cast") }.to change(Message, :count).by(1)

    expect(TalentPoolMembership.exists?(talent_pool: pool, member: person)).to be(true)
    stage = cycle.cast_assignment_stages.find_by(assignable: person)
    expect(stage).to be_finalized
    expect(stage).to be_cast
    message = Message.joins(:message_recipients).where(message_recipients: { recipient: person }).last
    expect(message.subject).to eq("Night Owls news")
    expect(message.body.to_plain_text).to include("Hello Wren, it's settled.")
    expect(flash[:notice]).to eq("Wren Ward has been added to the talent pool and notified.")

    doc = show_page
    expect(doc.text.squish).to include("Added to the talent pool on")
    expect(doc.at_css("button[data-modal-id='decide-cast-#{audition_request.id}']")).to be_nil
  end

  it "tells them they weren't chosen without adding them to the pool" do
    expect { decide("rejected") }.to change(Message, :count).by(1)

    expect(TalentPoolMembership.exists?(talent_pool: pool, member: person)).to be(false)
    expect(cycle.cast_assignment_stages.find_by(assignable: person)).to be_rejected
    expect(person.reload.notified_for_audition_cycle_id).to eq(cycle.id)
    expect(flash[:notice]).to eq("Wren Ward has been marked as not chosen and notified.")
  end

  it "says so when there's no email address to notify" do
    person.update_columns(email: nil)
    decide("cast")
    expect(flash[:notice]).to eq("Wren Ward has been added to the talent pool. No one has been notified, since there's no email address to send it to.")
  end

  it "badges decided requests in the list" do
    decide("rejected")
    get manage_signups_auditions_cycle_requests_path(production, cycle)
    row = Nokogiri::HTML(response.body).at_css("[data-request-row]")
    expect(row.text).to include("Not chosen")
  end

  context "when the cycle has audition sessions" do
    before { create(:audition_session, audition_cycle: cycle) }

    it "keeps decisions on the casting board" do
      expect(show_page.at_css("button[data-modal-id='decide-cast-#{audition_request.id}']")).to be_nil
      expect { decide("cast") }.not_to change(Message, :count)
      expect(flash[:alert]).to include("casting board")
    end
  end

  it "lists the sign-ups on the casting board when there are no sessions" do
    get manage_casting_select_signups_auditions_cycle_path(production, cycle)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Wren Ward")
  end

  it "sends the subject and body edited in Finalize & notify" do
    CastAssignmentStage.create!(audition_cycle: cycle, talent_pool: pool, assignable: person, decision_type: :cast)

    post manage_finalize_and_notify_signups_auditions_cycle_path(production, cycle),
         params: { cast_email_draft: { title: "Welcome, [Name]", body: "<div>[Name], you're in the pool.</div>" } }

    message = Message.joins(:message_recipients).where(message_recipients: { recipient: person }).last
    expect(message.subject).to eq("Welcome, Wren Ward")
    expect(message.body.to_plain_text).to include("Wren Ward, you're in the pool.")
  end
end
