# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Mics announcements", type: :request do
  let(:producer) { create(:user, password: "Password123!") }
  let(:other)    { create(:user, password: "Password123!") }
  let(:admin)    { create(:user, email_address: "boisvert@gmail.com", password: "Password123!") }
  let(:venue)    { create(:venue, name: "Beat Kitchen", city: "Chicago", state: "IL") }
  let!(:mic)     { create(:mic, venue: venue, name: "Beat Kitchen Mic") }
  let!(:link)    { create(:mic_producer, mic: mic, user: producer, role: :producer) }

  def sign_in_as(u)
    post handle_signin_path, params: { email_address: u.email_address, password: "Password123!" }
  end

  describe "POST /mics/m/:slug/announcements" do
    it "lets the producer post and persists the notify flag without sending email" do
      sign_in_as(producer)
      ActionMailer::Base.deliveries.clear

      expect {
        post mics_create_announcement_path(mic.slug), params: {
          title: "Tonight is on", body: "Doors at 7, sign up at 7:30.", notify_subscribers: "1"
        }
      }.to change { MicAnnouncement.count }.by(1)

      expect(ActionMailer::Base.deliveries).to be_empty

      a = MicAnnouncement.last
      expect(a.title).to eq("Tonight is on")
      expect(a.body).to eq("Doors at 7, sign up at 7:30.")
      expect(a.notify_subscribers).to be(true)
      expect(a.posted_by).to eq(producer)
      expect(a.posted_at).to be_within(5.seconds).of(Time.current)
      expect(response).to redirect_to(mics_producer_mic_path(mic.slug))
    end

    it "writes a MicEdit audit row" do
      sign_in_as(producer)
      expect {
        post mics_create_announcement_path(mic.slug), params: { body: "Quick update." }
      }.to change { MicEdit.where(field: "announcement").count }.by(1)
    end

    it "rejects non-producers with 403" do
      sign_in_as(other)
      expect {
        post mics_create_announcement_path(mic.slug), params: { body: "Tries to sneak in." }
      }.not_to(change { MicAnnouncement.count })
      expect(response).to have_http_status(:forbidden)
    end

    it "allows superadmins regardless of producer status" do
      sign_in_as(admin)
      expect {
        post mics_create_announcement_path(mic.slug), params: { body: "Admin override post." }
      }.to change { MicAnnouncement.count }.by(1)
    end

    it "redirects to signin when not authenticated" do
      post mics_create_announcement_path(mic.slug), params: { body: "Anon." }
      expect(response).to redirect_to(signin_path)
    end

    it "re-renders on validation failure (empty body)" do
      sign_in_as(producer)
      expect {
        post mics_create_announcement_path(mic.slug), params: { body: "" }
      }.not_to(change { MicAnnouncement.count })
      follow_redirect!
      expect(response.body).to include("Body").or include("blank")
    end
  end

  describe "detail page rendering" do
    it "shows the most recent announcements" do
      create(:mic_announcement, mic: mic, posted_by: producer,
             title: "Cancelled tonight", body: "Heater is broken, sorry!", posted_at: 1.hour.ago)
      get mics_detail_path(mic.slug)
      expect(response.body).to include("News from the producers")
      expect(response.body).to include("Cancelled tonight")
      expect(response.body).to include("Heater is broken")
    end

    it "omits the News section when there are no announcements" do
      get mics_detail_path(mic.slug)
      expect(response.body).not_to include("News from the producers")
    end
  end
end
