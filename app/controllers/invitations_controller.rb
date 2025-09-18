class InvitationsController < ApplicationController
  allow_unauthenticated_access only: [ :accept, :do_accept ]

  skip_before_action :require_current_production_company, only: [ :accept, :do_accept ]
  before_action :set_invitation, only: [ :accept, :do_accept ]


  def accept
    # Renders a form for the invitee to sign up or log in
  end

  def do_accept
    # Try and find the user accepting the invitation
    user = User.find_by(email_address: @invitation.email.downcase)

    # If the user exists, check their login
    if user
      if user.authenticate(params[:password])
        # User has entered the correct password
      else
        @authentication_error = true
        render :accept, status: :unprocessable_entity and return
      end
    else
      user = User.new(email_address: @invitation.email.downcase, password: params[:password])
      unless user.save
        # The user couldn't be created, so show an error
        flash.now[:alert] = user.errors.full_messages.to_sentence
        render :accept, status: :unprocessable_entity and return
      end
    end

    # Set a role and the production company
    unless UserRole.exists?(user: user, production_company: @invitation.production_company)
      UserRole.create!(user: user, production_company: @invitation.production_company, role: "member")
    end

    # Mark the invitation as accepted
    @invitation.update(accepted_at: Time.current)

    # Sign the user in
    start_new_session_for user

    # Set the current production company in session
    user_id = user&.id
    if user_id
      session[:current_production_company_id] ||= {}
      session[:current_production_company_id]["#{user_id}"] = @invitation.production_company.id
    end

    # And redirect
    redirect_to dashboard_path, notice: "You have joined #{@invitation.production_company.name}."
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
