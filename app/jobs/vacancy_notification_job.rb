# frozen_string_literal: true

class VacancyNotificationJob < ApplicationJob
  queue_as :default

  # Notify team members about a vacancy event
  # @param vacancy_id [Integer, Array<Integer>] The ID of the RoleVacancy, or
  #   the IDs of several created together (one notice names them all)
  # @param event [String] The type of event: "created", "filled", or "reclaimed"
  # @param sender_user_id [Integer, nil] Optional sender user ID
  def perform(vacancy_id, event, sender_user_id = nil)
    vacancies = RoleVacancy.where(id: vacancy_id).order(:id).to_a
    return if vacancies.empty?

    sender = User.find_by(id: sender_user_id) if sender_user_id
    if event == "created" && vacancies.size > 1
      VacancyNotificationService.notify_vacancies_created(vacancies, sender: sender)
    else
      VacancyNotificationService.notify_team(vacancies.first, event, sender: sender)
    end
  end
end
