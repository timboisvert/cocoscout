# frozen_string_literal: true

module Manage
  class PersonInvitationsController < Manage::ManageController
    allow_unauthenticated_access only: %i[accept do_accept decline]

    skip_before_action :require_current_organization, only: %i[accept do_accept decline]
    skip_before_action :show_manage_sidebar

    before_action :set_person_invitation, only: %i[accept do_accept decline]

    def accept
      # Check if user is already signed in with matching email
      @existing_user = Current.user && Current.user.email_address.downcase == @person_invitation.email.downcase

      # Renders a form for the invitee to accept or decline
    end

    def do_accept
      # Check if existing user is already signed in with matching email
      if Current.user && Current.user.email_address.downcase == @person_invitation.email.downcase
        user = Current.user
        person = user.person

        # Ensure the person is in the organization (if invitation has one)
        if @person_invitation.organization && !person.organizations.include?(@person_invitation.organization)
          person.organizations << @person_invitation.organization
        end

        # Add to talent pool if invitation was for a talent pool
        if @person_invitation.talent_pool && !@person_invitation.talent_pool.people.exists?(person.id)
          @person_invitation.talent_pool.people << person
        end

        # Mark the invitation as accepted
        @person_invitation.update(accepted_at: Time.current)

        # Mark the invitation as accepted and redirect to dashboard
        if @person_invitation.organization
          redirect_to my_dashboard_path, notice: "You've joined #{@person_invitation.organization.name}!", status: :see_other
        else
          redirect_to my_dashboard_path, notice: "Invitation accepted!", status: :see_other
        end
        return
      end

      # Not signed in - need to handle password
      user = User.find_by(email_address: @person_invitation.email.downcase)
      person = Person.find_by(email: @person_invitation.email.downcase)

      # If user already exists with a password, they shouldn't be here
      # They should already be linked to the person
      if user&.authenticate(params[:password])
        # User is signing in - this shouldn't normally happen for person invitations
        # but handle it gracefully
      elsif user
        # Set the password on the existing user or validate the new user
        user.password = params[:password]
        unless user.valid?
          @user = user
          render :accept, status: :unprocessable_entity and return
        end
        user.save!
      else
        # This shouldn't happen - user should exist when person invitation is created
        # But handle it gracefully
        user = User.new(email_address: @person_invitation.email.downcase, password: params[:password])
        unless user.save
          @user = user
          render :accept, status: :unprocessable_entity and return
        end
      end

      # Ensure person exists and is linked to user
      if person
        # Link existing person to user if not already linked
        unless person.user
          person.user = user
          person.save!
        end
      else
        # Create a person for this invitation
        person = Person.new(
          email: @person_invitation.email.downcase,
          name: @person_invitation.email.split("@").first,
          user: user
        )
        person.save!
      end

      # Ensure the person is in the organization (if invitation has one)
      if @person_invitation.organization && !person.organizations.include?(@person_invitation.organization)
        person.organizations << @person_invitation.organization
      end

      # Add to talent pool if invitation was for a talent pool
      if @person_invitation.talent_pool && !@person_invitation.talent_pool.people.exists?(person.id)
        @person_invitation.talent_pool.people << person
      end

      # Mark the invitation as accepted
      @person_invitation.update(accepted_at: Time.current)

      # Sign the user in
      start_new_session_for user

      # And redirect appropriately
      if @person_invitation.organization
        redirect_to my_dashboard_path, notice: "Welcome to #{@person_invitation.organization.name}!", status: :see_other
      else
        redirect_to my_dashboard_path, notice: "Welcome to CocoScout! Your account is ready.", status: :see_other
      end
    end

    def decline
      @person_invitation.update(declined_at: Time.current)

      # If they're already logged in, redirect to dashboard
      if Current.user
        redirect_to my_dashboard_path, notice: "You've declined the invitation.", status: :see_other
      else
        redirect_to root_path, notice: "You've declined the invitation.", status: :see_other
      end
    end

    private

    def set_person_invitation
      @person_invitation = PersonInvitation.find_by(token: params[:token])
      return if @person_invitation

      redirect_to root_path, alert: "Invalid or expired invitation"
    end
  end
end
