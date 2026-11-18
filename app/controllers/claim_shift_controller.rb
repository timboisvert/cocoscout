# frozen_string_literal: true

# The page a shift cover invitation links to (ClaimVacancyController's shape,
# for staff): no login, the shift and who else is on it, their own clashes
# as warnings, Claim or Decline. First to claim gets it.
class ClaimShiftController < ApplicationController
  allow_unauthenticated_access
  before_action :set_invitation

  def show
    load_shift
    @row = ShiftCandidates.new(@shift).row_for(@person) if @invitation.can_claim?
  end

  def claim
    if @invitation.claimed?
      redirect_to claim_shift_path(@invitation.token) and return
    end
    unless @invitation.can_claim?
      redirect_to claim_shift_path(@invitation.token), alert: "This shift has already been covered or is no longer open." and return
    end

    if @invitation.claim!
      redirect_to claim_shift_success_path(@invitation.token)
    else
      redirect_to claim_shift_path(@invitation.token), alert: "Someone else just claimed this shift."
    end
  end

  def success
    load_shift
  end

  def decline
    if @invitation.decline!
      redirect_to claim_shift_path(@invitation.token), notice: "Thanks for letting them know."
    else
      redirect_to claim_shift_path(@invitation.token)
    end
  end

  private

  def set_invitation
    @invitation = ShiftVacancyInvitation.includes(shift_vacancy: { shift: [ :house_role, :organization, :source, { shift_assignments: :person }, { shows: :production } ] })
                                        .find_by(token: params[:token])
    redirect_to root_path, alert: "Invalid or expired invitation link." unless @invitation
  end

  def load_shift
    @vacancy = @invitation.shift_vacancy
    @shift = @vacancy.shift
    @organization = @shift.organization
    @person = @invitation.person
  end
end
