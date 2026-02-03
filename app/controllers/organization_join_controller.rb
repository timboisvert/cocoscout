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
      # User not logged in - show signup form
      @existing_user = false
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

    # Case 2: New user or existing user not logged in
    email = params[:email]&.downcase&.strip
    password = params[:password]

    if email.blank? || password.blank?
      @email = email
      flash.now[:alert] = "Email and password are required"
      render :show, status: :unprocessable_entity
      return
    end

    # Check if user already exists
    user = User.find_by(email_address: email)

    if user
      # User exists - try to authenticate
      if user.authenticate(password)
        # Password correct - sign in and add to org
        start_new_session_for user
        add_user_to_organization(user)
      else
        # Wrong password - show error with link to sign in
        @email = email
        @existing_user_wrong_password = true
        render :show, status: :unprocessable_entity
      end
    else
      # New user - create account
      user = User.new(email_address: email, password: password)

      unless user.save
        @email = email
        @user = user
        render :show, status: :unprocessable_entity
        return
      end

      # Create a person for this user
      person = Person.create!(
        name: email.split("@").first.titleize,
        email: email,
        user_id: user.id
      )
      user.update!(default_person: person)

      # Notify admin

      # Sign in the new user
      start_new_session_for user

      # Add to organization
      add_user_to_organization(user)
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
      redirect_to my_dashboard_path, notice: "Welcome! You've joined #{@organization.name}."
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

    redirect_to my_dashboard_path, notice: "Welcome! You've joined #{@organization.name}."
  end
end
