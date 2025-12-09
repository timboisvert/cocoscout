# frozen_string_literal: true

module Manage
  class VacancyInvitationsController < ManageController
    before_action :set_production
    before_action :set_vacancy
    before_action :set_invitation

    def resend
      VacancyInvitationMailer.invitation_email(@invitation).deliver_later
      redirect_to manage_production_vacancy_path(@production, @vacancy),
                  notice: "Invitation resent to #{@invitation.person.name}."
    end

    private

    def set_production
      @production = Production.joins(:organization)
                              .where(organizations: { id: Current.user.organization_roles.select(:organization_id) })
                              .or(Production.joins(:organization).where(organizations: { owner_id: Current.user.id }))
                              .find(params[:production_id])
    end

    def set_vacancy
      @vacancy = @production.shows.joins(:role_vacancies).find_by!(role_vacancies: { id: params[:vacancy_id] }).role_vacancies.find(params[:vacancy_id])
    end

    def set_invitation
      @invitation = @vacancy.invitations.find(params[:id])
    end
  end
end
