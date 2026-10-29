# frozen_string_literal: true

require "rails_helper"

# Where the web says the app exists (Tim, 2026-10-28). Every link points
# straight at the store page; the marketing section sits at the bottom of the
# page, never above the ticketing pitch; a phone that opens cocoscout.com/app
# goes to its own store; the signed-in web gets Safari's banner, the manifest,
# and a one-time nudge on My Home from a phone's browser only.
RSpec.describe "Get the app", type: :request do
  let(:iphone_safari) { { "User-Agent" => "Mozilla/5.0 (iPhone; CPU iPhone OS 19_0 like Mac OS X) AppleWebKit/605.1.15 Version/19.0 Mobile/15E148 Safari/604.1" } }
  let(:android_chrome) { { "User-Agent" => "Mozilla/5.0 (Linux; Android 16; Pixel 9) AppleWebKit/537.36 Chrome/131.0 Mobile Safari/537.36" } }
  let(:in_app) { { "User-Agent" => "Mozilla/5.0 (iPhone) Hotwire Native iOS; Turbo Native iOS; bridge-components: [form menu];" } }

  describe "the marketing pages" do
    it "puts the section at the bottom of the landing page, after ticketing and the tiers, above the sign-up band, with both badges" do
      get root_path
      body = response.body
      section = body.index('id="app"')
      expect(section).to be_present
      expect(body.index("Instead of a ticketing site")).to be < section
      expect(body.index('id="tiers"')).to be < section
      expect(section).to be < body.index("Start running your production today.")
      expect(body).to include(AppStores::APP_STORE_URL, AppStores::PLAY_STORE_URL)
      expect(body).to include("CocoScout in your pocket.")
      expect(body).to include(%(href="#{get_the_app_path}"))
      expect(body).to include("now on iPhone and Android") # the hero line links down to it
      expect(body).to include("app/home") # a real screenshot, not a drawing
    end

    it "has the same section on For Performers and For Producers, above their bands" do
      get performers_path
      expect(response.body.index('id="app"')).to be < response.body.index("Make CocoScout your home base.")
      expect(response.body).to include("Now on iPhone and Android")

      get producers_path
      expect(response.body.index('id="app"')).to be < response.body.index("Run your whole production in one place.")
      expect(response.body).to include("For you and your team", "Production mode")
      expect(response.body).to include("app/production-casting") # production mode, as a real screenshot
    end

    it "carries the badges in every marketing footer" do
      get pricing_path
      footer = Nokogiri::HTML(response.body).at_css("footer")
      expect(footer.text).to include("Get the app")
      expect(footer.css("a[href='#{AppStores::APP_STORE_URL}']").size).to eq(1)
      expect(footer.css("a[href='#{AppStores::PLAY_STORE_URL}']").size).to eq(1)
    end
  end

  describe "cocoscout.com/app" do
    it "shows a desktop both badges and a QR code that scans to this same address" do
      get get_the_app_path
      expect(response).to have_http_status(:ok)
      doc = Nokogiri::HTML(response.body)
      expect(doc.css("[data-store-badges] a").map { |a| a["href"] }).to include(AppStores::APP_STORE_URL, AppStores::PLAY_STORE_URL)
      expect(doc.at_css("[data-app-qr] svg")).to be_present
      expect(response.body).to include("app/door") # the Door, as a real screenshot
      expect(response.body).to include("cocoscout.com/app")
    end

    it "sends an iPhone straight to the App Store and an Android phone to Google Play" do
      get get_the_app_path, headers: iphone_safari
      expect(response).to redirect_to(AppStores::APP_STORE_URL)

      get get_the_app_path, headers: android_chrome
      expect(response).to redirect_to(AppStores::PLAY_STORE_URL)
    end

    it "sends the app itself to its welcome screen, like every marketing page" do
      get get_the_app_path, headers: in_app
      expect(response).to redirect_to(welcome_path)
    end
  end

  describe "the signed-in web" do
    let(:password) { "Password123!" }
    let(:user) { create(:user, password: password) }
    let!(:person) { create(:person, user: user, name: "Ida Performer").tap { |p| user.update!(default_person: p) } }

    def sign_in(headers = {})
      post handle_signin_path, params: { email_address: user.email_address, password: password }, headers: headers
    end

    it "tells Safari and Chrome about the app from the page head, but not inside the app" do
      sign_in
      get my_dashboard_path
      expect(response.body).to include(%(<meta name="apple-itunes-app" content="app-id=#{AppStores::APP_STORE_ID}">))
      expect(response.body).to include('<link rel="manifest" href="/manifest.json">')

      sign_in(in_app)
      get my_dashboard_path, headers: in_app
      expect(response.body).not_to include("apple-itunes-app")
      expect(response.body).not_to include('rel="manifest"')
    end

    it "serves a manifest that prefers the Play Store app" do
      manifest = JSON.parse(Rails.root.join("public/manifest.json").read)
      expect(manifest["prefer_related_applications"]).to be(true)
      expect(manifest["related_applications"]).to include(include("platform" => "play", "id" => AppStores::ANDROID_PACKAGE))
      expect(manifest["icons"].map { |i| i["sizes"] }).to include("192x192", "512x512")
      manifest["icons"].each { |i| expect(Rails.root.join("public#{i['src']}")).to exist }
    end

    it "nudges a phone's browser once on My Home, naming that phone's own store, and never a desktop or the app" do
      sign_in(iphone_safari)
      get my_dashboard_path, headers: iphone_safari
      guide = Nokogiri::HTML(response.body).at_css("[data-intro-guide='get_the_app']")
      expect(guide).to be_present
      expect(guide.text).to include("Get the CocoScout app")
      links = guide.css("a").map { |a| [ a.text.squish, a["href"] ] }
      expect(links).to include([ "Get it on the App Store", AppStores::APP_STORE_URL ])
      expect(guide.text).not_to include("Google Play")
      # Both the X and "Not now" post the dismissal.
      expect(guide.css("form[action='#{guide_dismiss_path('get_the_app')}'] button").map { |b| b.text.squish }).to include("Not now")

      get my_dashboard_path, headers: android_chrome
      expect(response.body).to include("Get it on Google Play")
      expect(response.body).not_to include("Get it on the App Store")

      post guide_dismiss_path("get_the_app"), headers: iphone_safari
      get my_dashboard_path, headers: iphone_safari
      expect(response.body).not_to include("data-intro-guide=\"get_the_app\"")

      get my_dashboard_path
      expect(response.body).not_to include("data-intro-guide=\"get_the_app\"")

      sign_in(in_app)
      get my_dashboard_path, headers: in_app
      expect(response.body).not_to include("data-intro-guide=\"get_the_app\"")
    end
  end

  describe "every email's footer" do
    class GetTheAppFooterMailer < ApplicationMailer
      def hello
        mail(to: "someone@example.com", subject: "Hello") do |format|
          format.html { render html: "<p>hi</p>".html_safe, layout: "mailer" }
        end
      end
    end

    it "has two plain links to the stores" do
      html = GetTheAppFooterMailer.hello.message.html_part.decoded
      expect(html).to include("Get the CocoScout app")
      expect(html).to include(%(<a href="#{AppStores::APP_STORE_URL}">iPhone</a>))
      expect(html).to include(%(<a href="#{AppStores::PLAY_STORE_URL}">Android</a>))
    end
  end
end
