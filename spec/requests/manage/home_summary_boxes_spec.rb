# frozen_string_literal: true

require "rails_helper"

# The Home status bar says something about auditions and sign-ups only when
# there's something to say (they were summary boxes; pills since 2026-10-27).
RSpec.describe "Manage home status bar: auditions and sign-ups", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }
  let!(:show) { create(:show, production: production, date_and_time: 1.week.from_now) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def bar
    get manage_path
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body).at_css("[data-status-bar]")
  end

  context "on Pro with nothing going on" do
    let!(:org) { create(:organization, :pro, owner: owner) }

    it "has no status bar at all" do
      expect(bar).to be_nil
    end
  end

  context "on Pro with an open audition cycle" do
    let!(:org) { create(:organization, :pro, owner: owner) }
    let!(:cycle) { create(:audition_cycle, production: production, active: true) }
    let!(:request_record) { create(:audition_request, audition_cycle: cycle) }

    it "counts the sign-ups to review, linking to Sign-ups" do
      pill = bar.at_css("[data-status='signups']")
      expect(pill.text).to include("1 audition sign-up to review")
      expect(pill.at_css("a")["href"]).to eq(manage_signups_path)
    end
  end

  context "with a live sign-up form" do
    let!(:org) { create(:organization, :pro, owner: owner) }
    let!(:sign_up_form) { create(:sign_up_form, production: production) }
    let!(:instance) { create(:sign_up_form_instance, sign_up_form: sign_up_form, show: show) }

    it "says who's registered for the next event, linking to the form" do
      pill = bar.at_css("[data-status='registrations']")
      expect(pill.text).to include("registered for #{show.date_and_time.strftime('%A')}'s #{sign_up_form.name}")
      expect(pill.at_css("a")["href"]).to eq(manage_signups_form_path(production, sign_up_form))
    end
  end

  context "on the Producer plan with no sign-up forms" do
    let!(:org) { create(:organization, owner: owner) }

    it "has no status bar" do
      expect(bar).to be_nil
    end
  end
end
