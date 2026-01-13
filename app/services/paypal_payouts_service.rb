# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

class PaypalPayoutsService
  PRODUCTION_BASE_URL = "https://api-m.paypal.com"
  SANDBOX_BASE_URL = "https://api-m.sandbox.paypal.com"

  class PayoutError < StandardError; end
  class AuthenticationError < PayoutError; end
  class InsufficientFundsError < PayoutError; end
  class InvalidRecipientError < PayoutError; end
  class ConfigurationError < PayoutError; end

  def initialize
    @client_id = ENV.fetch("PAYPAL_CLIENT_ID", nil)
    @client_secret = ENV.fetch("PAYPAL_CLIENT_SECRET", nil)
    @sandbox = !Rails.env.production?
    @access_token = nil

    validate_configuration!
  end

  # Create a batch payout for multiple line items
  # Returns { success: true, batch_id: "...", items_processed: N } or { success: false, error: "..." }
  def create_batch_payout(line_items:, sender_batch_id: nil)
    return { success: false, error: "No line items provided" } if line_items.empty?

    # Filter to only items where payee has Venmo configured
    eligible_items = line_items.select(&:payee_venmo_ready?)
    return { success: false, error: "No eligible recipients with Venmo configured" } if eligible_items.empty?

    sender_batch_id ||= generate_batch_id

    payload = {
      sender_batch_header: {
        sender_batch_id: sender_batch_id,
        email_subject: "You have a payment from CocoScout!",
        email_message: "You have received a payment for your performance."
      },
      items: eligible_items.map { |li| build_payout_item(li) }
    }

    response = make_request(:post, "/v1/payments/payouts", payload)

    if response["batch_header"] && response["batch_header"]["payout_batch_id"]
      batch_id = response["batch_header"]["payout_batch_id"]

      # Update line items with batch info
      # The individual payout_item_id comes from the batch status check
      eligible_items.each do |li|
        li.mark_venmo_payout!(
          batch_id: batch_id,
          item_id: "pending_#{li.id}",
          status: "pending"
        )
      end

      {
        success: true,
        batch_id: batch_id,
        items_processed: eligible_items.count,
        items_skipped: line_items.count - eligible_items.count
      }
    else
      error_message = parse_error(response)
      { success: false, error: error_message }
    end
  rescue AuthenticationError => e
    { success: false, error: "Authentication failed: #{e.message}" }
  rescue InsufficientFundsError => e
    { success: false, error: e.message }
  rescue InvalidRecipientError => e
    { success: false, error: e.message }
  rescue PayoutError => e
    { success: false, error: e.message }
  rescue StandardError => e
    Rails.logger.error("PayPal Payouts error: #{e.class} - #{e.message}")
    Rails.logger.error(e.backtrace.first(10).join("\n"))
    { success: false, error: "An unexpected error occurred: #{e.message}" }
  end

  # Get status of a batch payout
  def get_batch_status(batch_id)
    response = make_request(:get, "/v1/payments/payouts/#{batch_id}")

    {
      success: true,
      batch_status: response.dig("batch_header", "batch_status"),
      items: response["items"]&.map do |item|
        {
          payout_item_id: item["payout_item_id"],
          transaction_status: item["transaction_status"],
          sender_item_id: item.dig("payout_item", "sender_item_id"),
          payout_item_fee: item.dig("payout_item_fee", "value"),
          error: item.dig("errors", "message")
        }
      end || []
    }
  rescue PayoutError => e
    { success: false, error: e.message }
  end

  # Get status of a single payout item
  def get_item_status(item_id)
    response = make_request(:get, "/v1/payments/payouts-item/#{item_id}")

    {
      success: true,
      status: response["transaction_status"],
      payout_item_id: response["payout_item_id"],
      sender_item_id: response.dig("payout_item", "sender_item_id"),
      error: response.dig("errors", "message")
    }
  rescue PayoutError => e
    { success: false, error: e.message }
  end

  # Check if service is properly configured
  def configured?
    @client_id.present? && @client_secret.present?
  end

  private

  def validate_configuration!
    return if configured?

    missing = []
    missing << "PAYPAL_CLIENT_ID" if @client_id.blank?
    missing << "PAYPAL_CLIENT_SECRET" if @client_secret.blank?

    raise ConfigurationError, "Missing environment variables: #{missing.join(', ')}"
  end

  def generate_batch_id
    "CocoScout_#{Time.current.strftime('%Y%m%d%H%M%S')}_#{SecureRandom.hex(4)}"
  end

  def build_payout_item(line_item)
    payee = line_item.payee
    show = line_item.show_payout.show

    {
      recipient_type: payee.venmo_identifier_type,
      amount: {
        value: format("%.2f", line_item.amount),
        currency: "USD"
      },
      receiver: format_receiver(payee),
      note: build_payment_note(show),
      sender_item_id: "line_item_#{line_item.id}",
      recipient_wallet: "Venmo"
    }
  end

  def format_receiver(payee)
    case payee.venmo_identifier_type
    when "PHONE"
      # PayPal expects phone in format with country code: +1XXXXXXXXXX
      digits = payee.venmo_identifier.gsub(/\D/, "")
      "+1#{digits}"
    when "EMAIL"
      payee.venmo_identifier
    when "USER_HANDLE"
      # Remove @ if present - PayPal expects just the handle
      payee.venmo_identifier.delete("@")
    else
      payee.venmo_identifier
    end
  end

  def build_payment_note(show)
    production_name = show.production.name
    show_date = show.date_and_time.strftime("%B %d, %Y")
    "Payment for #{production_name} - #{show_date}"
  end

  def base_url
    @sandbox ? SANDBOX_BASE_URL : PRODUCTION_BASE_URL
  end

  def access_token
    @access_token ||= fetch_access_token
  end

  def fetch_access_token
    uri = URI.parse("#{base_url}/v1/oauth2/token")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 30
    http.open_timeout = 10

    request = Net::HTTP::Post.new(uri.path)
    request.basic_auth(@client_id, @client_secret)
    request["Content-Type"] = "application/x-www-form-urlencoded"
    request.body = "grant_type=client_credentials"

    response = http.request(request)
    data = JSON.parse(response.body)

    if data["access_token"]
      data["access_token"]
    else
      error_desc = data["error_description"] || data["error"] || "Unknown authentication error"
      raise AuthenticationError, error_desc
    end
  rescue JSON::ParserError => e
    raise AuthenticationError, "Invalid response from PayPal: #{e.message}"
  rescue Net::TimeoutError, Errno::ECONNREFUSED => e
    raise PayoutError, "Network error connecting to PayPal: #{e.message}"
  end

  def make_request(method, path, body = nil)
    uri = URI.parse("#{base_url}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 60
    http.open_timeout = 10

    request = case method
    when :get
      Net::HTTP::Get.new(uri.request_uri)
    when :post
      Net::HTTP::Post.new(uri.request_uri)
    else
      raise ArgumentError, "Unsupported HTTP method: #{method}"
    end

    request["Authorization"] = "Bearer #{access_token}"
    request["Content-Type"] = "application/json"
    request.body = body.to_json if body

    response = http.request(request)

    Rails.logger.info("PayPal API #{method.upcase} #{path} - Status: #{response.code}")

    JSON.parse(response.body)
  rescue JSON::ParserError => e
    raise PayoutError, "Invalid JSON response from PayPal: #{e.message}"
  rescue Net::TimeoutError, Errno::ECONNREFUSED => e
    raise PayoutError, "Network error: #{e.message}"
  end

  def parse_error(response)
    name = response["name"]

    case name
    when "INSUFFICIENT_FUNDS"
      raise InsufficientFundsError, "Insufficient PayPal balance to process payouts"
    when "VALIDATION_ERROR"
      details = response["details"]&.map { |d| d["issue"] || d["description"] }&.compact&.join(", ")
      raise InvalidRecipientError, "Validation error: #{details || 'Unknown validation error'}"
    when "AUTHORIZATION_ERROR"
      raise AuthenticationError, response["message"] || "Authorization failed"
    else
      response["message"] || response["error_description"] || "Unknown error: #{name}"
    end
  end
end
