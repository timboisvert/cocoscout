# frozen_string_literal: true

module Ticketing
  class BaseService
    attr_reader :provider

    # Custom error classes
    class AuthenticationError < StandardError; end
    class RateLimitError < StandardError; end
    class ApiError < StandardError; end

    def initialize(provider)
      @provider = provider
    end

    # === Authentication ===
    # Override in subclasses for OAuth providers

    def self.authorization_url(organization, redirect_uri:)
      raise NotImplementedError, "#{name} does not support OAuth"
    end

    def self.exchange_code_for_tokens(code, redirect_uri:)
      raise NotImplementedError, "#{name} does not support OAuth"
    end

    def refresh_token!
      # No-op for API key providers
      # Override in OAuth providers
    end

    # === Capabilities ===
    # Override in subclasses to declare what the provider supports

    def capabilities
      {
        read_events: false,
        read_sales: false,
        read_pricing: false,
        write_events: false,
        webhooks: false
      }
    end

    def supports?(capability)
      capabilities[capability.to_sym] == true
    end

    # === Read Operations ===
    # Override in subclasses

    def fetch_events(since: nil)
      raise NotImplementedError
    end

    def fetch_event(provider_event_id)
      raise NotImplementedError
    end

    def fetch_occurrences(provider_event_id)
      raise NotImplementedError
    end

    def fetch_sales(provider_event_id, occurrence_id: nil, since: nil)
      raise NotImplementedError
    end

    def fetch_ticket_types(provider_event_id)
      raise NotImplementedError
    end

    # === URL Generation ===
    # Override in subclasses

    def dashboard_url
      raise NotImplementedError
    end

    def event_dashboard_url(provider_event_id)
      raise NotImplementedError
    end

    def ticket_page_url_for(show_link)
      raise NotImplementedError
    end

    protected

    def http_get(url, params: {}, headers: {})
      ensure_valid_credentials!

      uri = URI(url)
      uri.query = URI.encode_www_form(params) if params.any?

      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"
      apply_auth_headers(request)
      headers.each { |k, v| request[k] = v }

      execute_request(uri, request)
    end

    def http_post(url, body:, headers: {})
      ensure_valid_credentials!

      uri = URI(url)
      request = Net::HTTP::Post.new(uri)
      request.body = body.to_json
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json"
      apply_auth_headers(request)
      headers.each { |k, v| request[k] = v }

      execute_request(uri, request)
    end

    def ensure_valid_credentials!
      unless provider.has_credentials?
        raise AuthenticationError, "No credentials configured for #{provider.name}"
      end

      refresh_token! if provider.needs_token_refresh?
    end

    def apply_auth_headers(request)
      if provider.access_token.present?
        request["Authorization"] = "Bearer #{provider.access_token}"
      elsif provider.api_key.present?
        apply_api_key(request)
      end
    end

    def apply_api_key(request)
      # Default: Bearer token. Override in subclass for provider-specific formats.
      request["Authorization"] = "Bearer #{provider.api_key}"
    end

    def execute_request(uri, request)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.read_timeout = 30
      http.open_timeout = 10

      response = http.request(request)
      handle_response(response)
    end

    def handle_response(response)
      case response.code.to_i
      when 200..299
        parse_json(response.body)
      when 401, 403
        raise AuthenticationError, "Authentication failed (#{response.code}): #{response.body.truncate(200)}"
      when 429
        raise RateLimitError, "Rate limited: #{response.body.truncate(200)}"
      when 400..499
        raise ApiError, "Client error (#{response.code}): #{response.body.truncate(200)}"
      when 500..599
        raise ApiError, "Server error (#{response.code}): #{response.body.truncate(200)}"
      else
        raise ApiError, "Unexpected response (#{response.code}): #{response.body.truncate(200)}"
      end
    end

    def parse_json(body)
      return {} if body.blank?

      JSON.parse(body)
    rescue JSON::ParserError => e
      Rails.logger.error("Failed to parse JSON response: #{e.message}")
      { "raw_body" => body }
    end
  end
end
