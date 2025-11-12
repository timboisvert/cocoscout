class Manage::PersonInvitationsController < Manage::ManageController
  allow_unauthenticated_access only: [ :accept, :do_accept ]

  skip_before_action :require_current_organization, only: [ :accept, :do_accept ]
  skip_before_action :show_manage_sidebar

  before_action :set_person_invitation, only: [ :accept, :do_accept ]

  def accept
    # Renders a form for the invitee to set their password
  end

  def do_accept
    # Try and find the user accepting the invitation
    user = User.find_by(email_address: @person_invitation.email.downcase)
    person = Person.find_by(email: @person_invitation.email.downcase)

    # If user already exists with a password, they shouldn't be here
    # They should already be linked to the person
    if user && user.authenticate(params[:password])
      # User is signing in - this shouldn't normally happen for person invitations
      # but handle it gracefully
    else
      # Set the password on the existing user or validate the new user
      if user
        unless user.update(password: params[:password])
          flash.now[:alert] = user.errors.full_messages.to_sentence
          render :accept, status: :unprocessable_entity and return
        end
      else
        # This shouldn't happen - user should exist when person invitation is created
        # But handle it gracefully
        user = User.new(email_address: @person_invitation.email.downcase, password: params[:password])
        unless user.save
          flash.now[:alert] = user.errors.full_messages.to_sentence
          render :accept, status: :unprocessable_entity and return
        end
      end
    end

    # Ensure person exists and is linked to user
    unless person
      # Create a person for this invitation
      person = Person.new(
        email: @person_invitation.email.downcase,
        name: @person_invitation.email.split("@").first,
        user: user
      )
      person.save!
    else
      # Link existing person to user if not already linked
      unless person.user
        person.user = user
        person.save!
      end
    end

    # Ensure the person is in the organization
    unless person.organizations.include?(@person_invitation.organization)
      person.organizations << @person_invitation.organization
    end

    # Create a user role for this organization (default to "none" role)
    unless UserRole.exists?(user: user, organization: @person_invitation.organization)
      UserRole.create!(user: user, organization: @person_invitation.organization, company_role: "none")
    end

    # Mark the invitation as accepted
    @person_invitation.update(accepted_at: Time.current)

    # Sign the user in
    start_new_session_for user

    # Set the current production company in session
    user_id = user&.id
    if user_id
      session[:current_organization_id] ||= {}
      session[:current_organization_id]["#{user_id}"] = @person_invitation.organization.id
    end

    # And redirect to the directory
    redirect_to manage_people_path, notice: "Welcome to #{@person_invitation.organization.name}!", status: :see_other
  end

  private
  def set_person_invitation
    @person_invitation = PersonInvitation.find_by(token: params[:token])
    unless @person_invitation
      redirect_to root_path, alert: "Invalid or expired invitation"
    end
  end
end
