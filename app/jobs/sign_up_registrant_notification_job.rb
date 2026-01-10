# frozen_string_literal: true

class SignUpRegistrantNotificationJob < ApplicationJob
  queue_as :default

  # Available notification types:
  # - :confirmation - when user signs up for a slot
  # - :queued - when user joins the queue
  # - :slot_assigned - when user is moved from queue to a slot
  # - :slot_changed - when user changes their slot
  # - :cancelled - when registration is cancelled
  #
  # @param sign_up_registration_id [Integer] The ID of the SignUpRegistration
  # @param notification_type [Symbol] The type of notification to send
  def perform(sign_up_registration_id, notification_type)
    registration = SignUpRegistration.find_by(id: sign_up_registration_id)
    return unless registration

    # Validate notification type
    valid_types = %i[confirmation queued slot_assigned slot_changed cancelled]
    return unless valid_types.include?(notification_type.to_sym)

    # Check if registrant has an email
    recipient_email = registration.display_email
    return if recipient_email.blank?

    # Send the appropriate email
    SignUpRegistrantMailer.public_send(notification_type, registration).deliver_later
  end
end
