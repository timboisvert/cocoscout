# frozen_string_literal: true

require "net/http"

# The thin client for Google Calendar (Organization settings → Integrations →
# Google Calendar): Google's own sign-in, then one calendar CocoScout makes in
# the account and the events on it. The permission asked for covers only
# calendars this app created, so nothing here can read or change a calendar
# someone keeps by hand. Set GOOGLE_CALENDAR_CLIENT_ID and
# GOOGLE_CALENDAR_CLIENT_SECRET.
class GoogleCalendarApi
  class Error < StandardError; end
  # Google no longer honors the connection: access was withdrawn, or the
  # refresh token expired. The organization has to connect again.
  class Unauthorized < Error; end
  # The event, or the calendar, isn't there any more.
  class NotFound < Error; end
  # An event with that id is already on the calendar.
  class Conflict < Error; end
  # Google wants fewer calls for a moment. Wait, then carry on.
  class RateLimited < Error; end

  SCOPES = %w[openid email https://www.googleapis.com/auth/calendar.app.created].freeze
  AUTH_HOST = "accounts.google.com"
  TOKEN_HOST = "oauth2.googleapis.com"
  API_HOST = "www.googleapis.com"

  class << self
    def configured? = client_id.present? && client_secret.present?
    def client_id = ENV["GOOGLE_CALENDAR_CLIENT_ID"].presence || Rails.application.credentials.dig(:google_calendar, :client_id)
    def client_secret = ENV["GOOGLE_CALENDAR_CLIENT_SECRET"].presence || Rails.application.credentials.dig(:google_calendar, :client_secret)

    # Why Connect Google Calendar cannot start, in words for the page, or nil.
    def setup_problem
      "Google Calendar is not set up on this server yet." unless configured?
    end

    # Where "Connect Google Calendar" sends the owner. offline + consent so
    # Google hands back a refresh token every time.
    def authorize_url(state:, redirect_uri:)
      params = { client_id: client_id, redirect_uri: redirect_uri, response_type: "code", scope: SCOPES.join(" "),
                 access_type: "offline", prompt: "consent", include_granted_scopes: "true", state: state }
      "https://#{AUTH_HOST}/o/oauth2/v2/auth?#{params.to_query}"
    end

    # => { "access_token", "refresh_token", "expires_at", "email" }
    def exchange_code(code, redirect_uri:)
      body = token_request(code: code, client_id: client_id, client_secret: client_secret,
                           redirect_uri: redirect_uri, grant_type: "authorization_code")
      # Google lets someone untick a permission on its consent page.
      raise Error, "Google did not give CocoScout permission to keep a calendar. Connect again and leave that box ticked." unless body["scope"].to_s.include?("calendar.app.created")

      tokens_from(body).merge("refresh_token" => body["refresh_token"], "email" => email_from(body["id_token"])).compact
    end

    # => { "access_token", "expires_at" }; the refresh token stays the same.
    def refresh(refresh_token)
      tokens_from(token_request(refresh_token: refresh_token, client_id: client_id, client_secret: client_secret,
                                grant_type: "refresh_token"))
    end

    def revoke(token)
      request = Net::HTTP::Post.new("/revoke")
      request.set_form_data(token: token)
      perform(TOKEN_HOST, request)
    end

    def perform(host, request)
      http = Net::HTTP.new(host, 443)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 30
      response = http.request(request)
      body = response.body.present? ? JSON.parse(response.body) : {}
      return body if response.is_a?(Net::HTTPSuccess)

      message = error_message(body, response.code)
      raise Unauthorized, message if response.code == "401" || body["error"] == "invalid_grant"
      raise NotFound, message if %w[404 410].include?(response.code)
      raise Conflict, message if response.code == "409"
      raise RateLimited, message if rate_limited?(response.code, body)

      raise Error, message
    rescue JSON::ParserError
      raise Error, "Google answered with something that was not JSON"
    end

    private

    def token_request(form)
      request = Net::HTTP::Post.new("/token")
      request.set_form_data(form)
      perform(TOKEN_HOST, request)
    end

    def tokens_from(body)
      { "access_token" => body["access_token"], "expires_at" => (Time.current + body["expires_in"].to_i.seconds).iso8601 }
    end

    # The account's email, from the id token Google sends with the tokens.
    # It came straight from Google over TLS, so its payload is read as is.
    def email_from(id_token)
      payload = id_token.to_s.split(".")[1]
      return nil if payload.blank?

      JSON.parse(Base64.urlsafe_decode64(payload + ("=" * (-payload.size % 4))))["email"]
    rescue ArgumentError, JSON::ParserError
      nil
    end

    # 429, or a 403 whose reason is one of Google's "slow down" answers.
    def rate_limited?(code, body)
      return true if code == "429"
      return false unless code == "403" && body["error"].is_a?(Hash)

      reasons = Array(body.dig("error", "errors")).map { |error| error["reason"].to_s }
      reasons.any? { |reason| reason.match?(/rateLimitExceeded|quotaExceeded/i) } || body.dig("error", "message").to_s.match?(/rate limit/i)
    end

    def error_message(body, code)
      error = body["error"]
      detail = error.is_a?(Hash) ? error["message"] : (body["error_description"].presence || error)
      detail.presence || "Google answered #{code}"
    end
  end

  def initialize(access_token)
    @access_token = access_token
  end

  # A new calendar in the account; this app may write to it and to no other.
  def create_calendar(summary:, time_zone:, description: nil)
    post("/calendar/v3/calendars", { summary: summary, timeZone: time_zone, description: description }.compact)
  end

  def insert_event(calendar_id, event)
    post("#{events_path(calendar_id)}", event)
  end

  # The whole event written again: whatever was changed in Google is undone,
  # and an event deleted there comes back (status: "confirmed").
  def update_event(calendar_id, event_id, event)
    send_json(Net::HTTP::Put, "#{events_path(calendar_id)}/#{ERB::Util.url_encode(event_id)}", event)
  end

  def delete_event(calendar_id, event_id)
    request = Net::HTTP::Delete.new("#{events_path(calendar_id)}/#{ERB::Util.url_encode(event_id)}", headers)
    self.class.perform(API_HOST, request)
  rescue NotFound
    {} # already gone
  end

  private

  def events_path(calendar_id) = "/calendar/v3/calendars/#{ERB::Util.url_encode(calendar_id)}/events"
  def headers = { "Authorization" => "Bearer #{@access_token}", "Content-Type" => "application/json" }
  def post(path, body) = send_json(Net::HTTP::Post, path, body)

  def send_json(verb, path, body)
    request = verb.new(path, headers)
    request.body = body.to_json
    self.class.perform(API_HOST, request)
  end
end
