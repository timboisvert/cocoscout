# frozen_string_literal: true

module Manage
  class VacancyInvitationsController < ManageController
    before_action :set_production
    # Production team viewers look; managers change things (Tim, 2026-10-17).
    before_action :ensure_user_is_manager
    before_action :set_vacancy
    before_action :set_invitation

    def resend
      VacancyInvitationMailer.invitation_email(@invitation).deliver_later
      redirect_to manage_casting_vacancy_path(@production, @vacancy),
                  notice: "Invitation resent to #{@invitation.person.name}."
    end

    private

    def set_production
      @production = Current.organization.productions.find(params[:production_id])
    end

    def set_vacancy
      @vacancy = @production.shows.joins(:role_vacancies).find_by!(role_vacancies: { id: params[:vacancy_id] }).role_vacancies.find(params[:vacancy_id])
    end

    def set_invitation
      @invitation = @vacancy.invitations.find(params[:id])
    end
  end
end
