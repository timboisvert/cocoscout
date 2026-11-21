# frozen_string_literal: true

require "rails_helper"

# The organization's Sign-ups page (Tim, 2026-11-20): To review first, then
# one row per sign-up form or audition, closed ones behind a filter.
RSpec.describe "Manage sign-ups, organization level", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:circus) { create(:production, organization: org, name: "Bright Star Circus") }
  let!(:rising) { create(:production, organization: org, name: "Rising Stars") }
  let!(:quiet) { create(:production, organization: org, name: "Laugh-Along, Live!") }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def page_doc(params = {})
    get manage_signups_path(params)
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body)
  end

  context "with an open audition, a paused form with dates ahead, and a closed audition" do
    let!(:cycle) { create(:audition_cycle, production: circus, active: true) }
    let!(:unreviewed) { create(:audition_request, audition_cycle: cycle) }
    let!(:reviewed) { create(:audition_request, audition_cycle: cycle) }
    let!(:vote) { AuditionRequestVote.create!(audition_request: reviewed, user: owner, vote: :yes) }

    let!(:paused_form) { create(:sign_up_form, :inactive, production: rising, scope: "repeated", name: "Rising Stars Rehearsals Sign-ups") }
    let!(:future_show) { create(:show, production: rising, date_and_time: 1.week.from_now) }
    let!(:instance) { create(:sign_up_form_instance, sign_up_form: paused_form, show: future_show) }

    let!(:closed_cycle) { create(:audition_cycle, :closed, production: rising, active: true) }

    it "lists what's waiting on this user, counting only sign-ups they haven't voted on" do
      box = page_doc.at_css("#to-review")
      expect(box.text).to include("To review (1)", "Bright Star Circus", "1 sign-up to review")
      expect(box.at_css("a[href='#{manage_signups_auditions_cycle_requests_path(circus, cycle)}']")).to be_present
    end

    it "says the paused form is paused, and keeps closed auditions and empty productions out" do
      text = page_doc.text
      expect(text).to include("Rising Stars Rehearsals Sign-ups", "Paused", "Not taking sign-ups")
      expect(text).to include("2 signed up", "1 to review")
      expect(text).not_to include("Laugh-Along, Live!")
      expect(text).to include("Closed (1)")
      expect(text).not_to include("Closed #{closed_cycle.closes_at.strftime('%b %-d')}")
    end

    it "shows closed ones when asked, and filters by kind" do
      expect(page_doc(closed: "1").text).to include("Closed #{closed_cycle.closes_at.strftime('%b %-d')}")
      forms_only = page_doc(show: "forms")
      expect(forms_only.text).to include("Rising Stars Rehearsals Sign-ups")
      expect(forms_only.at_css("a[href='#{manage_signups_auditions_cycle_path(circus, cycle)}']")).to be_nil
    end

    it "gives home the same number" do
      get manage_path
      expect(response.body).to include("1 audition sign-up to review")
    end
  end

  context "once every sign-up has a vote" do
    let!(:cycle) { create(:audition_cycle, production: circus, active: true) }
    let!(:request_record) { create(:audition_request, audition_cycle: cycle) }
    let!(:vote) { AuditionRequestVote.create!(audition_request: request_record, user: owner, vote: :maybe) }

    it "has no To review box" do
      expect(page_doc.at_css("#to-review")).to be_nil
    end
  end
end
