class Manage::TeamInvitationsController < Manage::ManageController
  allow_unauthenticated_access only: [ :accept, :do_accept ]

  skip_before_action :require_current_organization, only: [ :accept, :do_accept ]
  skip_before_action :show_manage_sidebar

  before_action :set_team_invitation, only: [ :accept, :do_accept ]
  before_action :ensure_user_is_manager, except: [ :accept, :do_accept ]

  def accept
    # Renders a form for the invitee to sign up or log in
  end

  def do_accept
    # Try and find the user accepting the invitation
    # Also get their person
    user = User.find_by(email_address: @team_invitation.email.downcase)
    person = Person.find_by(email: @team_invitation.email.downcase)

    if user
      if user.authenticate(params[:password])
        # User has entered the correct password
      else
        @authentication_error = true
        @user = user
        render :accept, status: :unprocessable_entity and return
      end
    else
      user = User.new(email_address: @team_invitation.email.downcase)
      user.password = params[:password]
      user.person = person

      unless user.valid?
        @user = user
        render :accept, status: :unprocessable_entity and return
      end

      user.save!
    end

    # Now link the person and user if they aren't already linked. Create the
    # person if it doesn't exist
    if person
      person.user = user
      person.save!
    else
      person = Person.new(email: @team_invitation.email.downcase, name: @team_invitation.email.split("@").first, user: user)
      person.save!
      AuthMailer.signup(person.user).deliver_later
    end

    # Add the person to the organization if not already added
    unless person.organizations.include?(@team_invitation.organization)
      person.organizations << @team_invitation.organization
    end

    # Set a role and the organization
    unless UserRole.exists?(user: user, organization: @team_invitation.organization)
      UserRole.create!(user: user, organization: @team_invitation.organization, company_role: "none")
    end

    # Mark the invitation as accepted
    @team_invitation.update(accepted_at: Time.current)

    # Sign the user in
    start_new_session_for user

    # Set the current organization in session
    user_id = user&.id
    if user_id
      session[:current_organization_id] ||= {}
      session[:current_organization_id]["#{user_id}"] = @team_invitation.organization.id
    end

    # And redirect
    redirect_to manage_path, notice: "You have joined #{@team_invitation.organization.name}", status: :see_other
  end

  private
  def set_team_invitation
    @team_invitation = TeamInvitation.find_by(token: params[:token])
    unless @team_invitation
      redirect_to root_path, alert: "Invalid or expired invitation"
    end
  end

  def team_invitation_params
    params.require(:team_invitation).permit(:email)
  end
end
