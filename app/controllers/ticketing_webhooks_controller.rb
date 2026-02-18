# frozen_string_literal: true

class TicketingWebhooksController < ApplicationController
  # Skip CSRF for webhooks (no authentication needed - uses token-based auth)
  skip_before_action :verify_authenticity_token

  # POST /webhooks/ticketing/:provider_type/:token
  def receive
    provider = find_provider
    return render_not_found unless provider

    # Track that we received a webhook
    provider.touch(:webhook_last_received_at)

    # Log the webhook immediately
    webhook_log = create_webhook_log(provider)

    # Verify signature
    signature_result = verify_signature(provider)
    webhook_log.update!(signature_status: signature_result[:valid] ? :valid : :invalid)

    unless signature_result[:valid]
      webhook_log.mark_failed!("Signature verification failed: #{signature_result[:error]}")
      return render json: { error: "Invalid signature" }, status: :unauthorized
    end

    # Queue for async processing and return quickly
    webhook_log.process_async!

    render json: { received: true }, status: :ok
  end

  private

  def find_provider
    TicketingProvider.find_by(
      provider_type: params[:provider_type],
      webhook_endpoint_token: params[:token]
    )
  end

  def create_webhook_log(provider)
    adapter = provider.adapter
    parsed = adapter.parse_webhook(webhook_payload)

    WebhookLog.create!(
      ticketing_provider: provider,
      event_type: parsed[:event_type] || "unknown",
      external_id: parsed[:external_order_id] || parsed[:external_event_id],
      payload: webhook_payload,
      headers: relevant_headers,
      ip_address: request.remote_ip,
      status: :received
    )
  end

  def verify_signature(provider)
    adapter = provider.adapter
    adapter.verify_webhook_signature(request)
  end

  def webhook_payload
    @webhook_payload ||= begin
      if request.content_type&.include?("application/json")
        JSON.parse(request.raw_post)
      else
        params.to_unsafe_h.except(:controller, :action, :provider_type, :token)
      end
    rescue JSON::ParserError
      { raw: request.raw_post }
    end
  end

  def relevant_headers
    {
      content_type: request.content_type,
      user_agent: request.user_agent,
      # Include any signature headers
      eventbrite_signature: request.headers["X-Eventbrite-Signature"],
      ticket_tailor_signature: request.headers["Ticket-Tailor-Signature"]
    }.compact
  end

  def render_not_found
    render json: { error: "Not found" }, status: :not_found
  end
end
