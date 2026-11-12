# frozen_string_literal: true

require "net/http"

# The thin client for Square's API (plan §9.3): OAuth with Square's own
# sign-in, then locations, the catalog's categories, closed orders and
# payments. Nothing here changes anything in Square; the scopes are read
# only. Set SQUARE_APPLICATION_ID, SQUARE_APPLICATION_SECRET and, for
# webhooks, SQUARE_WEBHOOK_SIGNATURE_KEY; SQUARE_ENVIRONMENT=sandbox points
# at the sandbox.
class SquareApi
  class Error < StandardError; end

  VERSION = "2026-01-22"
  SCOPES = %w[MERCHANT_PROFILE_READ ORDERS_READ PAYMENTS_READ ITEMS_READ].freeze

  class << self
    def configured? = application_id.present? && application_secret.present?
    def application_id = ENV["SQUARE_APPLICATION_ID"].presence || Rails.application.credentials.dig(:square, :application_id)
    def application_secret = ENV["SQUARE_APPLICATION_SECRET"].presence || Rails.application.credentials.dig(:square, :application_secret)
    def webhook_signature_key = ENV["SQUARE_WEBHOOK_SIGNATURE_KEY"].presence || Rails.application.credentials.dig(:square, :webhook_signature_key)
    def sandbox? = (ENV["SQUARE_ENVIRONMENT"].presence || Rails.application.credentials.dig(:square, :environment)).to_s == "sandbox"
    def host = sandbox? ? "connect.squareupsandbox.com" : "connect.squareup.com"

    # The secret pasted from the wrong page of Square's Developer Console:
    # an access token starts with EAAA, an application secret with sq0csb.
    def secret_looks_like_token? = application_secret.to_s.start_with?("EAAA")

    # Why Connect with Square cannot start, in words for the page, or nil.
    def setup_problem
      return "Square is not set up on this server yet." unless configured?
      return "The Square secret on this server is an access token, not the Application Secret. In Square's Developer Console, the Application Secret is on the app's OAuth page." if secret_looks_like_token?

      nil
    end

    # Where "Connect with Square" sends the owner.
    def authorize_url(state:)
      params = { client_id: application_id, scope: SCOPES.join(" "), session: "false", state: state }
      "https://#{host}/oauth2/authorize?#{params.to_query}"
    end

    def exchange_code(code, redirect_uri:)
      post_unauthenticated("/oauth2/token", client_id: application_id, client_secret: application_secret,
                                            code: code, grant_type: "authorization_code", redirect_uri: redirect_uri)
    end

    def refresh(refresh_token)
      post_unauthenticated("/oauth2/token", client_id: application_id, client_secret: application_secret,
                                            refresh_token: refresh_token, grant_type: "refresh_token")
    end

    def revoke(access_token)
      request = Net::HTTP::Post.new("/oauth2/revoke", "Authorization" => "Client #{application_secret}", "Content-Type" => "application/json", "Square-Version" => VERSION)
      request.body = { client_id: application_id, access_token: access_token }.to_json
      perform(request)
    end

    # Square signs each webhook body with the signature key and the
    # notification URL, HMAC-SHA256, base64.
    def webhook_signature_valid?(url, body, signature)
      return false if webhook_signature_key.blank? || signature.blank?

      expected = Base64.strict_encode64(OpenSSL::HMAC.digest("sha256", webhook_signature_key, url + body))
      ActiveSupport::SecurityUtils.secure_compare(expected, signature)
    end

    private

    def post_unauthenticated(path, body)
      request = Net::HTTP::Post.new(path, "Content-Type" => "application/json", "Square-Version" => VERSION)
      request.body = body.to_json
      perform(request)
    end

    def perform(request)
      http = Net::HTTP.new(host, 443)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 30
      response = http.request(request)
      body = response.body.present? ? JSON.parse(response.body) : {}
      raise Error, error_message(body, response.code) unless response.is_a?(Net::HTTPSuccess)

      body
    rescue JSON::ParserError
      raise Error, "Square answered with something that was not JSON"
    end

    def error_message(body, code)
      detail = Array(body["errors"]).map { |e| e["detail"] || e["code"] }.compact.join("; ")
      detail.presence || body["message"].presence || "Square answered #{code}"
    end
  end

  def initialize(access_token)
    @access_token = access_token
  end

  def merchant
    get("/v2/merchants/me")["merchant"] || {}
  end

  def locations
    get("/v2/locations")["locations"] || []
  end

  # Every category, item and variation, so an order's lines can be read as
  # our categories: variation → item → category.
  def catalog
    objects = []
    cursor = nil
    loop do
      page = get("/v2/catalog/list", types: "CATEGORY,ITEM", cursor: cursor)
      objects.concat(page["objects"] || [])
      cursor = page["cursor"]
      break if cursor.blank?
    end
    objects
  end

  # Completed orders at a location closed in the span, oldest first.
  def orders(location_id, from:, to:)
    results = []
    cursor = nil
    loop do
      body = { location_ids: [ location_id ], cursor: cursor, limit: 500,
               query: { filter: { state_filter: { states: [ "COMPLETED" ] },
                                  date_time_filter: { closed_at: { start_at: from.iso8601, end_at: to.iso8601 } } },
                        sort: { sort_field: "CLOSED_AT", sort_order: "ASC" } } }.compact
      page = post("/v2/orders/search", body)
      results.concat(page["orders"] || [])
      cursor = page["cursor"]
      break if cursor.blank?
    end
    results
  end

  # Payments at a location in the span: tips, fees and refunds live here.
  def payments(location_id, from:, to:)
    results = []
    cursor = nil
    loop do
      page = get("/v2/payments", location_id: location_id, begin_time: from.iso8601, end_time: to.iso8601, sort_order: "ASC", limit: 100, cursor: cursor)
      results.concat(page["payments"] || [])
      cursor = page["cursor"]
      break if cursor.blank?
    end
    results
  end

  private

  def get(path, params = {})
    query = params.compact.to_query
    request = Net::HTTP::Get.new(query.present? ? "#{path}?#{query}" : path, headers)
    self.class.send(:perform, request)
  end

  def post(path, body)
    request = Net::HTTP::Post.new(path, headers)
    request.body = body.to_json
    self.class.send(:perform, request)
  end

  def headers
    { "Authorization" => "Bearer #{@access_token}", "Content-Type" => "application/json", "Square-Version" => VERSION }
  end
end
