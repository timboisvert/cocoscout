# frozen_string_literal: true

module Manage
  class TeamInvitationsController < Manage::ManageController
    allow_unauthenticated_access only: %i[accept do_accept]

    skip_before_action :require_current_organization, only: %i[accept do_accept]
    skip_before_action :show_manage_sidebar

    before_action :set_team_invitation, only: %i[accept do_accept]
    before_action :ensure_user_is_manager, except: %i[accept do_accept]

    def accept
      # Load all profiles with this email for selection
      @available_profiles = Person.where(email: @team_invitation.email.downcase)
      @existing_user = User.find_by(email_address: @team_invitation.email.downcase)
    end

    def do_accept
      # Try and find the user accepting the invitation
      user = User.find_by(email_address: @team_invitation.email.downcase)

      # Set up instance variables for the view (in case we need to re-render)
      @available_profiles = Person.where(email: @team_invitation.email.downcase)
      @existing_user = user

      # Use the person_id stored on the invitation (selected when inviting)
      # Fall back to first profile with this email if no person_id was set
      if @team_invitation.person_id.present?
        person = Person.find_by(id: @team_invitation.person_id)
      else
        person = @available_profiles.first
      end

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
        AdminMailer.user_account_created(user).deliver_later
      end

      # Now link the person and user if they aren't already linked. Create the
      # person if it doesn't exist
      if person
        person.user = user
        person.save!
      else
        person = Person.new(email: @team_invitation.email.downcase, name: @team_invitation.email.split("@").first,
                            user: user)
        person.save!
        AuthMailer.signup(person.user).deliver_later
      end

      # Add the person to the organization if not already added
      unless person.organizations.include?(@team_invitation.organization)
        person.organizations << @team_invitation.organization
      end

      # Set a role and the organization (viewer by default, notifications off)
      # Store the person_id so we know which profile was invited for this team role
      existing_role = OrganizationRole.find_by(user: user, organization: @team_invitation.organization)
      if existing_role
        # Upgrade "member" to "viewer" if this is an org team invitation (not production-specific)
        # "member" is a minimal role for production-only access, org invites should be "viewer" or higher
        updates = {}
        if existing_role.company_role == "member" && !@team_invitation.production_invite?
          updates[:company_role] = "viewer"
        end
        if @team_invitation.person_id.present? && existing_role.person_id != @team_invitation.person_id
          updates[:person_id] = @team_invitation.person_id
        end
        existing_role.update!(updates) if updates.any?
      else
        OrganizationRole.create!(
          user: user,
          organization: @team_invitation.organization,
          company_role: "viewer",
          notifications_enabled: false,
          person_id: person&.id
        )
      end

      # If this is a production-specific invitation, create the production permission
      if @team_invitation.production_invite?
        ProductionPermission.find_or_create_by!(user: user, production: @team_invitation.production) do |perm|
          perm.role = @team_invitation.invitation_role || "viewer"
          perm.notifications_enabled = @team_invitation.invitation_notifications_enabled.nil? ? true : @team_invitation.invitation_notifications_enabled
        end
      end

      # Mark the invitation as accepted
      @team_invitation.update(accepted_at: Time.current)

      # Sign the user in
      start_new_session_for user

      # Set the current organization in session
      user_id = user&.id
      if user_id
        session[:current_organization_id] ||= {}
        session[:current_organization_id][user_id.to_s] = @team_invitation.organization.id
      end

      # And redirect
      redirect_to manage_path, notice: "You have joined #{@team_invitation.organization.name}", status: :see_other
    end

    private

    def set_team_invitation
      @team_invitation = TeamInvitation.find_by(token: params[:token])
      return if @team_invitation

      redirect_to root_path, alert: "Invalid or expired invitation"
    end

    def team_invitation_params
      params.require(:team_invitation).permit(:email)
    end
  end
end
