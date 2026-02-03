# frozen_string_literal: true

class VacancyNotificationJob < ApplicationJob
  queue_as :default

  # Notify team members about a vacancy event
  # @param vacancy_id [Integer] The ID of the RoleVacancy
  # @param event [String] The type of event: "created", "filled", or "reclaimed"
  # @param sender_user_id [Integer, nil] Optional sender user ID
  def perform(vacancy_id, event, sender_user_id = nil)
    vacancy = RoleVacancy.find_by(id: vacancy_id)
    return unless vacancy

    sender = User.find_by(id: sender_user_id) if sender_user_id
    VacancyNotificationService.notify_team(vacancy, event, sender: sender)
  end
end
