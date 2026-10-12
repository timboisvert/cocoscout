# frozen_string_literal: true

# Both arrive with the rpush gem; list them in the Gemfile if it ever goes.
require "jwt"
require "net-http2"

# Apple's push service, spoken to directly over HTTP/2 with token auth: a
# short-lived token signed with CocoScout's APNs key (.p8), which, unlike the
# old certificates, never expires. Settings come from the environment:
#
#   APNS_KEY_ID       the key's ID from the Apple developer site
#   APNS_TEAM_ID      the team ID (3Y9EQJP24Y)
#   APNS_PRIVATE_KEY  the .p8 file, base64-encoded onto one line (or as is)
#   APNS_TOPIC        the app's bundle ID; com.cocoscout.app unless set
#
# Without them, nothing is sent (configured? is false), so development and
# test never reach Apple unless asked to.
#
#   ApnsClient.open("production") { |apns| apns.deliver(token, payload) }
class ApnsClient
  HOSTS = { "production" => "https://api.push.apple.com", "sandbox" => "https://api.sandbox.push.apple.com" }.freeze
  # Apple refuses tokens older than an hour, and throttles refreshing more
  # often than every 20 minutes.
  TOKEN_LIFETIME = 50.minutes

  Result = Data.define(:status, :reason) do
    def ok? = status == 200

    # The app was deleted, or the token was never valid for this app: forget it.
    def gone? = status == 410 || %w[BadDeviceToken Unregistered DeviceTokenNotForTopic].include?(reason)
  end

  @token_lock = Mutex.new

  class << self
    def configured?
      %w[APNS_KEY_ID APNS_TEAM_ID APNS_PRIVATE_KEY].all? { |name| ENV[name].present? }
    end

    def open(environment)
      apns = new(environment)
      yield apns
    ensure
      apns&.close
    end

    def topic = ENV["APNS_TOPIC"].presence || "com.cocoscout.app"

    # Shared across threads and jobs until it's close to an hour old.
    def auth_token
      @token_lock.synchronize do
        if @auth_token.nil? || @auth_token_at < TOKEN_LIFETIME.ago
          @auth_token = JWT.encode({ iss: ENV.fetch("APNS_TEAM_ID"), iat: Time.now.to_i }, signing_key, "ES256",
                                   { kid: ENV.fetch("APNS_KEY_ID") })
          @auth_token_at = Time.current
        end
        @auth_token
      end
    end

    private

    def signing_key
      raw = ENV.fetch("APNS_PRIVATE_KEY")
      pem = raw.include?("BEGIN") ? raw.gsub("\\n", "\n") : Base64.decode64(raw)
      OpenSSL::PKey::EC.new(pem)
    end
  end

  attr_reader :host

  def initialize(environment)
    @host = HOSTS.fetch(environment.to_s, HOSTS["production"])
  end

  # payload: the whole notification, { aps: {...}, plus our own keys }.
  def deliver(device_token, payload, push_type: "alert")
    headers = { "authorization" => "bearer #{self.class.auth_token}", "apns-topic" => self.class.topic,
                "apns-push-type" => push_type, "apns-priority" => push_type == "background" ? "5" : "10" }
    response = connection.call(:post, "/3/device/#{device_token}", body: payload.to_json, headers: headers, timeout: 10)
    Result.new(status: response.status.to_i, reason: reason_in(response.body))
  end

  def close
    @connection&.close
  end

  private

  def connection
    @connection ||= NetHttp2::Client.new(@host, connect_timeout: 5)
  end

  def reason_in(body)
    body.present? ? JSON.parse(body)["reason"] : nil
  rescue JSON::ParserError
    nil
  end
end
