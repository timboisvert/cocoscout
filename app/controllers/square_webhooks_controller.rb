# frozen_string_literal: true

# Square tells us during the night as orders close and payments land, so a
# day is filling in before anyone looks. Each event re-pulls that merchant's
# day; the signature is checked first and each event runs once.
class SquareWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  allow_unauthenticated_access

  def create
    body = request.body.read
    return head :unauthorized unless SquareApi.webhook_signature_valid?(request.original_url, body, request.headers["x-square-hmacsha256-signature"])

    event = JSON.parse(body)
    return head :ok unless WebhookEvent.claim!(provider: "square", event_id: event["event_id"].to_s, event_type: event["type"])

    merchant_id = event["merchant_id"].to_s
    Integration.connected.square.find_each do |integration|
      next unless integration.merchant_id == merchant_id

      date = SettlementDay.day_for(integration.organization, Time.current)
      SquarePullJob.perform_later(integration.id, from: date - 1, to: date, trigger: "webhook")
    end
    WebhookEvent.finish!(provider: "square", event_id: event["event_id"].to_s)
    head :ok
  rescue JSON::ParserError
    head :bad_request
  end
end
