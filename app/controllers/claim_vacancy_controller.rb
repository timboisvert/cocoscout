# frozen_string_literal: true

class ClaimVacancyController < ApplicationController
  allow_unauthenticated_access
  before_action :set_invitation

  def show
    @vacancy = @invitation.role_vacancy
    @role = @vacancy.role
    @show = @vacancy.show
    @production = @show.production

    # Get other cast members for display (excluding the person who vacated)
    @other_cast_assignments = @show.show_person_role_assignments
                                   .includes(:role)
                                   .where.not(
                                     assignable_type: @vacancy.vacated_by_type,
                                     assignable_id: @vacancy.vacated_by_id
                                   )
                                   .order("roles.position ASC")
  end

  def claim
    if @invitation.expired?
      redirect_to claim_vacancy_path(@invitation.token), alert: "This invitation has expired or the vacancy has been filled."
      return
    end

    if @invitation.claimed?
      redirect_to claim_vacancy_path(@invitation.token), alert: "You've already claimed this role."
      return
    end

    if @invitation.claim!
      # The claim! method handles updating the vacancy status and creating the cast assignment
      @vacancy = @invitation.role_vacancy

      redirect_to claim_vacancy_success_path(@invitation.token)
    else
      redirect_to claim_vacancy_path(@invitation.token), alert: "Something went wrong. Please try again."
    end
  end

  def success
    @vacancy = @invitation.role_vacancy
    @role = @vacancy.role
    @show = @vacancy.show
    @production = @show.production
  end

  def decline
    if @invitation.expired?
      redirect_to my_dashboard_path, alert: "This invitation has expired or the vacancy has been filled."
      return
    end

    if @invitation.decline!
      redirect_to my_dashboard_path, notice: "You've declined the invitation."
    else
      redirect_to my_dashboard_path, alert: "Something went wrong. Please try again."
    end
  end

  private

  def set_invitation
    @invitation = RoleVacancyInvitation.find_by!(token: params[:token])
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "Invalid or expired invitation link."
  end
end
