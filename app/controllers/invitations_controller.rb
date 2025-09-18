class InvitationsController < ApplicationController
  skip_before_action :require_current_production_company, only: [ :accept, :do_accept ]
  before_action :set_invitation, only: [ :accept, :do_accept ]


  def accept
    # Renders a form for the invitee to sign up or log in
  end

  def do_accept
    # Accept the invite: associate user with company (create user if needed)
    user = User.find_by(email_address: @invitation.email.downcase)
    if user.nil?
      user = User.new(email_address: @invitation.email.downcase, password: params[:password], password_confirmation: params[:password_confirmation])
      unless user.save
        flash.now[:alert] = user.errors.full_messages.to_sentence
        render :accept, status: :unprocessable_entity and return
      end
    end
    unless UserRole.exists?(user: user, production_company: @invitation.production_company)
      UserRole.create!(user: user, production_company: @invitation.production_company, role: "member")
    end
    @invitation.update(accepted_at: Time.current)
    # TODO: sign in user if desired
    redirect_to root_path, notice: "You have joined #{@invitation.production_company.name}."
  end

  private
  def set_invitation
    @invitation = Invitation.find_by(token: params[:token])
    unless @invitation
      redirect_to root_path, alert: "Invalid or expired invitation."
    end
  end

  def invitation_params
    params.require(:invitation).permit(:email)
  end
end
