# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module CalendarSync
  class GoogleService < BaseService
    GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"
    GOOGLE_CALENDAR_API_BASE = "https://www.googleapis.com/calendar/v3"

    def create_event(show)
      ensure_valid_token!

      response = make_request(
        :post,
        "/calendars/#{calendar_id}/events",
        event_payload(show)
      )

      if response.is_a?(Hash) && response["id"]
        subscription.calendar_events.create!(
          show: show,
          provider_event_id: response["id"],
          last_synced_at: Time.current,
          last_sync_hash: CalendarEvent.generate_sync_hash(show)
        )
      else
        raise "Failed to create Google Calendar event: #{response}"
      end
    end

    def update_event(calendar_event)
      ensure_valid_token!

      response = make_request(
        :put,
        "/calendars/#{calendar_id}/events/#{calendar_event.provider_event_id}",
        event_payload(calendar_event.show)
      )

      if response.is_a?(Hash) && response["id"]
        calendar_event.mark_synced!
      else
        raise "Failed to update Google Calendar event: #{response}"
      end
    end

    def delete_event(calendar_event)
      ensure_valid_token!

      make_request(
        :delete,
        "/calendars/#{calendar_id}/events/#{calendar_event.provider_event_id}"
      )

      calendar_event.destroy!
    rescue StandardError => e
      # If the event doesn't exist in Google, just delete our record
      if e.message.include?("404") || e.message.include?("Not Found")
        calendar_event.destroy!
      else
        raise
      end
    end

    def self.authorization_url(redirect_uri:, state:)
      params = {
        client_id: Rails.application.credentials.dig(:google, :client_id),
        redirect_uri: redirect_uri,
        response_type: "code",
        scope: "https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/userinfo.email",
        access_type: "offline",
        prompt: "consent",
        state: state
      }

      "https://accounts.google.com/o/oauth2/v2/auth?#{URI.encode_www_form(params)}"
    end

    def self.exchange_code_for_tokens(code:, redirect_uri:)
      uri = URI.parse(GOOGLE_TOKEN_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri.path)
      request.set_form_data(
        client_id: Rails.application.credentials.dig(:google, :client_id),
        client_secret: Rails.application.credentials.dig(:google, :client_secret),
        code: code,
        grant_type: "authorization_code",
        redirect_uri: redirect_uri
      )

      response = http.request(request)
      JSON.parse(response.body)
    end

    def self.get_user_email(access_token)
      uri = URI.parse("https://www.googleapis.com/oauth2/v2/userinfo")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Get.new(uri.path)
      request["Authorization"] = "Bearer #{access_token}"

      response = http.request(request)
      data = JSON.parse(response.body)
      data["email"]
    end

    private

    def calendar_id
      subscription.calendar_id || "primary"
    end

    def ensure_valid_token!
      return if subscription.token_valid?

      refresh_access_token!
    end

    def refresh_access_token!
      uri = URI.parse(GOOGLE_TOKEN_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri.path)
      request.set_form_data(
        client_id: Rails.application.credentials.dig(:google, :client_id),
        client_secret: Rails.application.credentials.dig(:google, :client_secret),
        refresh_token: subscription.refresh_token,
        grant_type: "refresh_token"
      )

      response = http.request(request)
      data = JSON.parse(response.body)

      if data["access_token"]
        subscription.update!(
          access_token: data["access_token"],
          token_expires_at: Time.current + data["expires_in"].to_i.seconds
        )
      else
        raise "Failed to refresh Google access token: #{data}"
      end
    end

    def make_request(method, path, body = nil)
      uri = URI.parse("#{GOOGLE_CALENDAR_API_BASE}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = case method
      when :get then Net::HTTP::Get.new(uri.request_uri)
      when :post then Net::HTTP::Post.new(uri.request_uri)
      when :put then Net::HTTP::Put.new(uri.request_uri)
      when :patch then Net::HTTP::Patch.new(uri.request_uri)
      when :delete then Net::HTTP::Delete.new(uri.request_uri)
      end

      request["Authorization"] = "Bearer #{subscription.access_token}"
      request["Content-Type"] = "application/json"

      if body
        request.body = body.to_json
      end

      response = http.request(request)

      return nil if response.code == "204"

      JSON.parse(response.body)
    end

    def event_payload(show)
      payload = {
        summary: event_title(show),
        description: event_description(show),
        start: {
          dateTime: event_start_time(show).iso8601,
          timeZone: Time.zone.name
        },
        end: {
          dateTime: event_end_time(show).iso8601,
          timeZone: Time.zone.name
        }
      }

      location = event_location(show)
      payload[:location] = location if location.present?

      if show.canceled?
        payload[:status] = "cancelled"
      end

      payload
    end
  end
end
