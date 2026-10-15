# frozen_string_literal: true

# Arrives with the rpush gem; list it in the Gemfile if that ever goes.
require "googleauth"

# Google's push service for the Android app (Firebase Cloud Messaging, HTTP
# v1), signed in as CocoScout's Firebase service account. Settings come from
# the environment:
#
#   FCM_SERVICE_ACCOUNT_JSON  the service account's key file from Firebase
#                             (Project settings → Service accounts), as is or
#                             base64-encoded onto one line (.kamal/secrets
#                             encodes it)
#
# Without it, nothing is sent (configured? is false), so development and test
# never reach Google unless asked to.
#
#   FcmClient.open { |fcm| fcm.deliver(token, data) }
class FcmClient
  HOST = "fcm.googleapis.com"
  SCOPE = "https://www.googleapis.com/auth/firebase.messaging"

  Result = Data.define(:status, :reason) do
    def ok? = status == 200

    # The app was uninstalled, or the token belongs to another Firebase
    # project: forget it.
    def gone? = status == 404 || %w[UNREGISTERED SENDER_ID_MISMATCH].include?(reason)
  end

  @lock = Mutex.new

  class << self
    def configured? = ENV["FCM_SERVICE_ACCOUNT_JSON"].present?

    def open
      fcm = new
      yield fcm
    ensure
      fcm&.close
    end

    def service_account
      raw = ENV.fetch("FCM_SERVICE_ACCOUNT_JSON").strip
      JSON.parse(raw.start_with?("{") ? raw : Base64.decode64(raw))
    end

    # Google's access token lasts an hour; shared across jobs until it's
    # five minutes from running out.
    def access_token
      @lock.synchronize do
        @credentials ||= Google::Auth::ServiceAccountCredentials.make_creds(
          json_key_io: StringIO.new(service_account.to_json), scope: SCOPE
        )
        @credentials.fetch_access_token! if @credentials.access_token.nil? || @credentials.expires_within?(300)
        @credentials.access_token
      end
    end
  end

  # data: string keys and values only (FCM's rule). The app builds the
  # notification from them (CocoScoutMessagingService), so it looks the same
  # whether or not the app is open.
  def deliver(device_token, data)
    message = { token: device_token, data: data.transform_keys(&:to_s).transform_values(&:to_s),
                android: { priority: "HIGH" } }
    request = Net::HTTP::Post.new("/v1/projects/#{project_id}/messages:send",
                                  "Authorization" => "Bearer #{self.class.access_token}", "Content-Type" => "application/json")
    request.body = { message: message }.to_json
    response = connection.request(request)
    Result.new(status: response.code.to_i, reason: reason_in(response.body))
  end

  def close
    @connection&.finish if @connection&.started?
  end

  private

  def project_id
    @project_id ||= self.class.service_account.fetch("project_id")
  end

  def connection
    @connection ||= Net::HTTP.start(HOST, 443, use_ssl: true, open_timeout: 5, read_timeout: 10)
  end

  # FCM's own error code (UNREGISTERED…) when it gives one, else Google's status.
  def reason_in(body)
    error = JSON.parse(body.to_s)["error"] || {}
    Array(error["details"]).filter_map { |detail| detail["errorCode"] }.first || error["status"]
  rescue JSON::ParserError
    nil
  end
end
