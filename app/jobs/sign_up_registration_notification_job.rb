# frozen_string_literal: true

class SignUpRegistrationNotificationJob < ApplicationJob
  queue_as :default

  # Notify production team when someone submits a sign-up registration
  # @param sign_up_registration_id [Integer] The ID of the SignUpRegistration
  def perform(sign_up_registration_id)
    registration = SignUpRegistration.find_by(id: sign_up_registration_id)
    return unless registration

    SignUpProducerNotificationService.notify_team(registration)
  end
end
