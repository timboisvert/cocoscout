# frozen_string_literal: true

class OrganizationJoinController < ApplicationController
  allow_unauthenticated_access only: [ :show, :join ]

  before_action :set_organization

  def show
    # Resume session to check if user is logged in (allow_unauthenticated_access skips this)
    resume_session

    if Current.user
      # User is logged in
      person = Current.user.person || Current.user.default_person
      @already_member = person&.organizations&.include?(@organization)
      @existing_user = true unless @already_member
    else
      # Not signed in: the page carries the sign-in screen's first step (the
      # email address). Signing in or creating an account there comes
      # straight back here, signed in, to join with one tap.
      @existing_user = false
      session[:return_to] = join_organization_path(params[:token])
    end
  end

  def join
    # Resume session to check if user is logged in (allow_unauthenticated_access skips this)
    resume_session

    # Case 1: Already logged in
    if Current.user
      add_current_user_to_organization
      return
    end

    # Case 2: not signed in. The page no longer posts here signed out (its
    # form is the sign-in screen's email step), so this is an older copy of
    # the page posting an email and a password. An existing account's right
    # password still joins; everyone else goes through the sign-in screen,
    # where a new address is confirmed with a code before its account is made.
    email = params[:email]&.downcase&.strip
    user = User.find_by(email_address: email) if email.present?

    if user && params[:password].present? && user.authenticate(params[:password])
      start_new_session_for user, sign_in_method: "password"
      add_user_to_organization(user)
    elsif user && params[:password].present?
      @email = email
      @existing_user_wrong_password = true
      render :show, status: :unprocessable_content
    else
      redirect_to signin_path(start_over: 1, email_address: email.presence, redirect_to: join_organization_path(params[:token]))
    end
  end

  private

  def set_organization
    @organization = Organization.find_by(invite_token: params[:token])
    if @organization.nil?
      redirect_to root_path, alert: "This invite link is invalid or has expired."
    end
  end

  def add_current_user_to_organization
    person = Current.user.person || Current.user.default_person

    if person.nil?
      # Create a person for this user
      person = Person.create!(
        name: Current.user.email_address.split("@").first.titleize,
        email: Current.user.email_address,
        user_id: Current.user.id
      )
      Current.user.update!(default_person: person)
    end

    if person.organizations.include?(@organization)
      redirect_to my_dashboard_path, notice: "You're already a member of #{@organization.name}!"
    else
      # Add person to organization
      @organization.people << person
      # The dashboard greets them with what joining means (see the
      # just-joined panel in my/dashboard/index).
      flash[:just_joined_organization_id] = @organization.id
      redirect_to my_dashboard_path
    end
  end

  def add_user_to_organization(user)
    person = user.person || user.default_person

    if person.nil?
      # Create a person for this user
      person = Person.create!(
        name: user.email_address.split("@").first.titleize,
        email: user.email_address,
        user_id: user.id
      )
      user.update!(default_person: person)
    end

    # Add person to organization
    @organization.people << person unless person.organizations.include?(@organization)

    flash[:just_joined_organization_id] = @organization.id
    redirect_to my_dashboard_path
  end
end
