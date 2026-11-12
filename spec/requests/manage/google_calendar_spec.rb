# frozen_string_literal: true

require "rails_helper"

# Organization settings → Integrations → Google Calendar (Tim, 2026-11-11):
# the connect round trip with its state check, the calendar CocoScout makes,
# what goes on it, each room's color, Sync now, disconnect.
RSpec.describe "Manage::GoogleCalendar", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner, name: "Stars & Garters") }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:location) { create(:location, organization: org, name: "Stars & Garters") }
  let!(:mainstage) { location.location_spaces.create!(name: "Mainstage") }
  let!(:ruse) { location.location_spaces.create!(name: "Ruse Room") }

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  def connected!
    org.integrations.create!(provider: "google_calendar", status: "connected", connected_by: owner, connected_at: Time.current,
                             settings: { "calendar_id" => "cal-1", "calendar_name" => "Stars & Garters (CocoScout)", "account_email" => "boxoffice@example.com" },
                             tokens: { "access_token" => "tok", "refresh_token" => "ref", "expires_at" => 50.minutes.from_now.iso8601 })
  end

  before do
    allow(GoogleCalendarApi).to receive_messages(client_id: "client-id", client_secret: "client-secret")
    sign_in(owner)
  end

  it "is in the organization's catalog of integrations" do
    get section_manage_organization_path(org, section: "integrations")

    expect(response.body).to include("Calendars", "Google Calendar", "Connect Google Calendar")
  end

  describe "connecting" do
    it "sends the owner to Google asking only for calendars CocoScout makes, and the callback makes one and fills it" do
      post manage_connect_organization_google_calendar_path(org)
      expect(response).to redirect_to(%r{\Ahttps://accounts\.google\.com/o/oauth2/v2/auth\?})
      query = Rack::Utils.parse_query(URI(response.location).query)
      expect(query["scope"]).to eq("openid email https://www.googleapis.com/auth/calendar.app.created")
      expect(query).to include("access_type" => "offline", "prompt" => "consent")

      allow(GoogleCalendarApi).to receive(:exchange_code).with("the-code", redirect_uri: manage_google_calendar_callback_url)
        .and_return({ "access_token" => "tok", "refresh_token" => "ref", "expires_at" => 1.hour.from_now.iso8601, "email" => "boxoffice@example.com" })
      api = instance_double(GoogleCalendarApi)
      allow(GoogleCalendarApi).to receive(:new).with("tok").and_return(api)
      allow(api).to receive(:create_calendar).and_return({ "id" => "cal-9" })

      expect {
        get manage_google_calendar_callback_path, params: { code: "the-code", state: query["state"] }
      }.to have_enqueued_job(GoogleCalendarFullSyncJob).with(org.id)

      expect(response).to redirect_to(manage_organization_google_calendar_path(org))
      integration = org.integrations.google_calendar.first
      expect(integration).to be_connected
      expect(integration.calendar_id).to eq("cal-9")
      expect(integration.account_email).to eq("boxoffice@example.com")
      expect(api).to have_received(:create_calendar).with(hash_including(summary: "Stars & Garters (CocoScout)"))
    end

    it "picks the same calendar back up on connecting again" do
      org.integrations.create!(provider: "google_calendar", status: "disconnected",
                               settings: { "calendar_id" => "cal-old", "calendar_name" => "Stars & Garters (CocoScout)" })
      post manage_connect_organization_google_calendar_path(org)
      state = Rack::Utils.parse_query(URI(response.location).query)["state"]
      allow(GoogleCalendarApi).to receive(:exchange_code)
        .and_return({ "access_token" => "tok", "refresh_token" => "ref", "expires_at" => 1.hour.from_now.iso8601, "email" => "boxoffice@example.com" })
      api = instance_double(GoogleCalendarApi)
      allow(GoogleCalendarApi).to receive(:new).with("tok").and_return(api)
      allow(api).to receive(:get_calendar).with("cal-old").and_return({ "id" => "cal-old", "summary" => "Stars & Garters (CocoScout)" })
      allow(api).to receive(:create_calendar)

      get manage_google_calendar_callback_path, params: { code: "the-code", state: state }

      expect(org.integrations.google_calendar.sole.calendar_id).to eq("cal-old")
      expect(api).not_to have_received(:create_calendar)
      expect(flash[:notice]).to include("keeping the same calendar")
    end

    it "refuses a callback whose state doesn't match" do
      post manage_connect_organization_google_calendar_path(org)
      allow(GoogleCalendarApi).to receive(:exchange_code)

      get manage_google_calendar_callback_path, params: { code: "the-code", state: "someone-elses" }

      expect(GoogleCalendarApi).not_to have_received(:exchange_code)
      expect(org.integrations.google_calendar).to be_empty
    end

    it "says so when the server has no Google keys" do
      allow(GoogleCalendarApi).to receive_messages(client_id: nil, client_secret: nil)

      get manage_organization_google_calendar_path(org)

      expect(response.body).to include("Google Calendar is not set up on this server yet.")
    end
  end

  describe "the settings page" do
    before { connected! }

    it "shows the calendar, each room with Google's colors, and one color for everything else" do
      get manage_organization_google_calendar_path(org)

      expect(response).to have_http_status(:ok)
      page = Nokogiri::HTML(response.body)
      expect(response.body).to include("Stars &amp; Garters (CocoScout)", "boxoffice@example.com", "Rehearsal", "Open Mic", "Block the whole rental time when a date is under contract",
                                       "A canceled date leaves the calendar.", "Mainstage", "Ruse Room", "Everything else")
      expect(page.css("input[name='room_colors[#{ruse.id}]']").size).to eq(11)
      expect(page.css("input[name='other_color']").size).to eq(11)
      expect(response.body).not_to include("Online", "Hold")
    end

    it "leaves an archived location's rooms out of the colors" do
      ruse.location.update!(archived_at: Time.current)

      get manage_organization_google_calendar_path(org)

      expect(Nokogiri::HTML(response.body).css("input[name^='room_colors']")).to be_empty
    end

    it "saves what goes on it, how titles read and the colors, and brings the calendar up to date" do
      expect {
        patch manage_organization_google_calendar_path(org), params: {
          event_types: { show: "1", rehearsal: "0" }, title: { room: "1", call_time: "0", start_at_call: "0" },
          room_colors: { ruse.id => "4", mainstage.id => "7", "999999" => "3" }, other_color: "8"
        }
      }.to have_enqueued_job(GoogleCalendarFullSyncJob).with(org.id)

      integration = org.integrations.google_calendar.first
      expect(integration.calendar_event_type?("show")).to be(true)
      expect(integration.calendar_event_type?("rehearsal")).to be(false)
      expect(integration.calendar_title_part?("call_time")).to be(false)
      expect(integration.room_color(ruse)).to eq("4")
      expect(integration.room_color(mainstage)).to eq("7")
      expect(integration.settings["room_colors"].keys).to contain_exactly(ruse.id.to_s, mainstage.id.to_s)
      expect(integration.other_color).to eq("8")
    end

    it "writes everything again on Sync now" do
      expect {
        post manage_sync_organization_google_calendar_path(org)
      }.to have_enqueued_job(GoogleCalendarFullSyncJob).with(org.id, force: true)
    end

    it "disconnects, leaving the calendar in Google" do
      allow(GoogleCalendarApi).to receive(:revoke)

      delete manage_organization_google_calendar_path(org)

      expect(GoogleCalendarApi).to have_received(:revoke).with("ref")
      expect(org.integrations.google_calendar.first).not_to be_connected
      follow_redirect!
      expect(response.body).to include("Google Calendar is disconnected")
    end
  end

  it "is the owner's and managers' page only" do
    member = create(:user, password: password)
    create(:organization_role, user: member, organization: org, company_role: "member")
    delete signout_path rescue nil
    sign_in(member)

    get manage_organization_google_calendar_path(org)

    expect(response).not_to have_http_status(:ok)
  end
end
