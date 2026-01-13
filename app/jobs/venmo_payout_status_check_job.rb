# frozen_string_literal: true

class VenmoPayoutStatusCheckJob < ApplicationJob
  queue_as :default

  # Retry on network errors with exponential backoff
  retry_on PaypalPayoutsService::PayoutError, wait: :polynomially_longer, attempts: 5

  def perform(batch_id, check_count: 0)
    service = PaypalPayoutsService.new
    result = service.get_batch_status(batch_id)

    unless result[:success]
      Rails.logger.error("Failed to get batch status for #{batch_id}: #{result[:error]}")
      return
    end

    batch_status = result[:batch_status]
    Rails.logger.info("Batch #{batch_id} status: #{batch_status}")

    # Update individual line items
    result[:items]&.each do |item|
      update_line_item_from_response(item)
    end

    # Re-check if batch is still processing
    if batch_status.in?(%w[PENDING PROCESSING]) && check_count < 20
      # Exponential backoff: 2min, 4min, 8min, etc. up to 30min max
      wait_time = [ 2.minutes * (2 ** check_count), 30.minutes ].min
      VenmoPayoutStatusCheckJob.set(wait: wait_time).perform_later(batch_id, check_count: check_count + 1)
    end
  end

  private

  def update_line_item_from_response(item)
    sender_item_id = item[:sender_item_id]
    return unless sender_item_id.present?

    # Extract line item ID from sender_item_id (format: "line_item_123")
    match = sender_item_id.match(/line_item_(\d+)/)
    return unless match

    line_item_id = match[1].to_i
    line_item = ShowPayoutLineItem.find_by(id: line_item_id)
    return unless line_item

    # Map PayPal status to our internal status
    status = map_paypal_status(item[:transaction_status])
    error = item[:error]

    # Update the payout_reference_id with the actual PayPal payout_item_id
    if item[:payout_item_id].present? && line_item.payout_reference_id&.start_with?("pending_")
      line_item.update!(payout_reference_id: item[:payout_item_id])
    end

    # Update status
    line_item.update_payout_status!(status: status, error: error)

    Rails.logger.info("Updated line item #{line_item_id} status to #{status}")
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn("Line item not found for sender_item_id: #{sender_item_id}")
  rescue StandardError => e
    Rails.logger.error("Error updating line item #{sender_item_id}: #{e.message}")
  end

  def map_paypal_status(paypal_status)
    case paypal_status
    when "SUCCESS" then "success"
    when "FAILED" then "failed"
    when "PENDING" then "pending"
    when "UNCLAIMED" then "unclaimed"
    when "RETURNED" then "returned"
    when "ONHOLD" then "pending"
    when "BLOCKED" then "blocked"
    when "REFUNDED" then "returned"
    when "REVERSED" then "returned"
    else
      Rails.logger.warn("Unknown PayPal status: #{paypal_status}")
      "pending"
    end
  end
end
