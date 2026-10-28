# frozen_string_literal: true

# Where the CocoScout app lives, and which store a phone belongs to.
#
# Every "get the app" link on the web points straight at the store page
# (Tim, 2026-10-28): no interstitial of our own. The one address people can
# say out loud or print, cocoscout.com/app, sends a phone to its own store
# and shows a desktop both badges and a QR code.
module AppStores
  APP_STORE_ID   = "6821995221"
  APP_STORE_URL  = "https://apps.apple.com/app/cocoscout/id#{APP_STORE_ID}".freeze
  ANDROID_PACKAGE = "com.cocoscout.app"
  PLAY_STORE_URL = "https://play.google.com/store/apps/details?id=#{ANDROID_PACKAGE}".freeze

  STORES = {
    ios:     { name: "the App Store", url: APP_STORE_URL,  button: "Get it on the App Store" },
    android: { name: "Google Play",   url: PLAY_STORE_URL, button: "Get it on Google Play" }
  }.freeze

  # The store for a phone's web browser: :ios, :android, or nil for a desktop,
  # an unknown device, or the CocoScout app itself (it already is the app).
  def self.platform(user_agent)
    ua = user_agent.to_s
    return nil if ua.include?("Turbo Native")
    return :ios if ua.match?(/iPhone|iPad|iPod/)
    return :android if ua.include?("Android")

    nil
  end

  def self.url(platform) = STORES.fetch(platform)[:url]
  def self.name(platform) = STORES.fetch(platform)[:name]
  def self.button(platform) = STORES.fetch(platform)[:button]
end
