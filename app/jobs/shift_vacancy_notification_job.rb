# frozen_string_literal: true

# A shift vacancy was covered or taken back: tell the chosen managers (and,
# when it's covered, whoever dropped it). Off the request, like every notice.
class ShiftVacancyNotificationJob < ApplicationJob
  queue_as :default

  def perform(shift_vacancy_id, event, invitation_id = nil)
    vacancy = ShiftVacancy.find_by(id: shift_vacancy_id)
    return unless vacancy

    case event.to_s
    when "filled" then ShiftVacancyNotificationService.notify_filled(vacancy) if vacancy.filled?
    when "reclaimed" then ShiftVacancyNotificationService.notify_reclaimed(vacancy)
    when "claimed"
      invitation = vacancy.invitations.find_by(id: invitation_id)
      ShiftVacancyNotificationService.notify_claimed(invitation) if invitation&.claimed?
    end
  end
end
