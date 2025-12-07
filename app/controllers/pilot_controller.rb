# frozen_string_literal: true

class PilotController < ApplicationController
  include Authentication

  before_action :require_authentication
  before_action :require_superadmin
  skip_before_action :show_my_sidebar
  before_action :initialize_pilot_session

  def index
    # Load state from session
    @talent_state = session[:pilot_talent_state] || {}
    @producer_state = session[:pilot_producer_state] || {}

    # If we have an organization but no production name in session, look it up
    return unless @producer_state[:organization_id].present? && @producer_state[:production_name].blank?

    organization = Organization.find_by(id: @producer_state[:organization_id])
    return unless organization

    first_production = organization.productions.order(created_at: :asc).first
    return unless first_production

    @producer_state[:production_id] = first_production.id
    @producer_state[:production_name] = first_production.name
    # Update session
    session[:pilot_producer_state][:production_id] = first_production.id
    session[:pilot_producer_state][:production_name] = first_production.name
  end

  def reset_talent
    session[:pilot_talent_state] = nil
    redirect_to pilot_path, notice: "Talent setup reset"
  end

  def reset_producer
    session[:pilot_producer_state] = nil
    redirect_to pilot_path, notice: "Producer setup reset"
  end

  def resend_invitation
    user = User.find(params[:user_id])
    organization_id = params[:organization_id]

    # Find most recent invitation or create new one
    person_invitation = PersonInvitation.where(email: user.email_address)
    person_invitation = if organization_id.present?
                          person_invitation.where(organization_id: organization_id).order(created_at: :desc).first
    else
                          person_invitation.where(organization_id: nil).order(created_at: :desc).first
    end

    # Create new invitation if none exists
    if person_invitation.nil?
      person_invitation = PersonInvitation.create!(
        email: user.email_address,
        organization_id: organization_id
      )
    end

    # Send email
    if organization_id.present?
      organization = Organization.find(organization_id)
      Manage::PersonMailer.person_invitation(
        person_invitation,
        "You've been invited to join #{organization.name} on CocoScout",
        "Welcome to CocoScout!\n\n#{organization.name} is using CocoScout to manage its productions, auditions, and casting.\n\nTo get started, please click the link below to set a password and create your account."
      ).deliver_later
    else
      Manage::PersonMailer.person_invitation(
        person_invitation,
        "You've been invited to join CocoScout",
        "Welcome to CocoScout!\n\nYou've been invited to join CocoScout, the platform for managing productions, auditions, and casting.\n\nTo get started, please click the link below to set a password and create your account."
      ).deliver_later
    end

    render json: {
      success: true,
      message: "Invitation email resent to #{user.email_address}"
    }
  rescue StandardError => e
    render json: { success: false, errors: [ e.message ] }, status: :unprocessable_entity
  end

  def create_talent
    ActiveRecord::Base.transaction do
      email = params[:email]
      full_name = params[:name]

      # Find or create user
      @user = User.find_by(email_address: email)
      user_already_existed = @user.present?

      if @user.nil?
        @user = User.new(
          email_address: email,
          password: SecureRandom.hex(16)
        )

        unless @user.save
          render json: { success: false, errors: @user.errors.full_messages }, status: :unprocessable_entity
          return
        end
      end

      # Find or create person
      @person = @user.person
      if @person.nil?
        @person = Person.new(
          name: full_name,
          email: email,
          user: @user
        )

        unless @person.save
          raise ActiveRecord::Rollback
          render json: { success: false, errors: @person.errors.full_messages }, status: :unprocessable_entity
          return
        end
      end

      # Only send invitation for new users
      unless user_already_existed
        # Create person invitation (without organization for talent)
        person_invitation = PersonInvitation.create!(
          email: @person.email
        )

        # Send invitation email
        Manage::PersonMailer.person_invitation(
          person_invitation,
          "You've been invited to join CocoScout",
          "Welcome to CocoScout!\n\nYou've been invited to join CocoScout, the platform for managing productions, auditions, and casting.\n\nTo get started, please click the link below to set a password and create your account."
        ).deliver_later
      end

      # Store in session
      session[:pilot_talent_state] = {
        user_id: @user.id,
        person_id: @person.id,
        email: @user.email_address,
        name: @person.name,
        completed: true
      }

      message = if user_already_existed
                  "User already exists. Selected #{@user.email_address}"
      else
                  "Pilot talent created and invitation sent to #{@user.email_address}"
      end

      render json: {
        success: true,
        message: message,
        user: { id: @user.id, email: @user.email_address },
        person: { id: @person.id, name: @person.name },
        already_existed: user_already_existed
      }
    end
  rescue StandardError => e
    render json: { success: false, errors: [ e.message ] }, status: :unprocessable_entity
  end

  def create_producer_user
    ActiveRecord::Base.transaction do
      email = params[:email]
      full_name = params[:name]

      # Find or create user
      @user = User.find_by(email_address: email)
      user_already_existed = @user.present?

      if @user.nil?
        @user = User.new(
          email_address: email,
          password: SecureRandom.hex(16)
        )

        unless @user.save
          render json: { success: false, errors: @user.errors.full_messages }, status: :unprocessable_entity
          return
        end
      end

      # Find or create person
      @person = @user.person
      if @person.nil?
        @person = Person.new(
          name: full_name,
          email: email,
          user: @user
        )

        unless @person.save
          raise ActiveRecord::Rollback
          render json: { success: false, errors: @person.errors.full_messages }, status: :unprocessable_entity
          return
        end
      end

      # Only send invitation for new users
      unless user_already_existed
        # Create person invitation (without organization for producer)
        person_invitation = PersonInvitation.create!(
          email: @person.email
        )

        # Send invitation email
        Manage::PersonMailer.person_invitation(
          person_invitation,
          "You've been invited to join CocoScout",
          "Welcome to CocoScout!\n\nYou've been invited to join CocoScout, the platform for managing productions, auditions, and casting.\n\nTo get started, please click the link below to set a password and create your account."
        ).deliver_later
      end

      # Store in session for PRODUCER
      session[:pilot_producer_state] = {
        user_id: @user.id,
        person_id: @person.id,
        email: @user.email_address,
        name: @person.name
      }

      message = if user_already_existed
                  "User already exists. Selected #{@user.email_address}"
      else
                  "Producer user created and invitation sent to #{@user.email_address}"
      end

      render json: {
        success: true,
        message: message,
        user: { id: @user.id, email: @user.email_address },
        person: { id: @person.id, name: @person.name },
        already_existed: user_already_existed
      }
    end
  rescue StandardError => e
    render json: { success: false, errors: [ e.message ] }, status: :unprocessable_entity
  end

  # ==== STEP-BY-STEP PRODUCER CREATION ====

  def create_producer_org
    ActiveRecord::Base.transaction do
      user = User.find(params[:user_id])

      # Create organization with user as owner
      @organization = Organization.new(
        name: params[:organization_name],
        owner: user
      )

      unless @organization.save
        render json: { success: false, errors: @organization.errors.full_messages }, status: :unprocessable_entity
        return
      end

      # Add user as manager
      OrganizationRole.create!(
        user: user,
        organization: @organization,
        company_role: "manager"
      )

      # Associate person with organization
      user.person.organizations << @organization unless user.person.organizations.include?(@organization)

      # Store in session
      session[:pilot_producer_state] = {
        user_id: user.id,
        person_id: user.person.id,
        email: user.email_address,
        name: user.person.name,
        organization_id: @organization.id,
        organization_name: @organization.name
      }

      render json: {
        success: true,
        message: "Organization created for #{user.email_address}",
        organization: { id: @organization.id, name: @organization.name }
      }
    end
  rescue StandardError => e
    render json: { success: false, errors: [ e.message ] }, status: :unprocessable_entity
  end

  def create_producer_location
    ActiveRecord::Base.transaction do
      organization = Organization.find(params[:organization_id])

      # Create location
      @location = Location.new(
        name: params[:location_name],
        address1: params[:address1],
        address2: params[:address2],
        city: params[:city],
        state: params[:state],
        postal_code: params[:postal_code],
        organization: organization
      )

      unless @location.save
        render json: { success: false, errors: @location.errors.full_messages }, status: :unprocessable_entity
        return
      end

      # Update session
      session[:pilot_producer_state][:location_id] = @location.id
      session[:pilot_producer_state][:location_name] = @location.name

      render json: {
        success: true,
        message: "Location created successfully",
        location: { id: @location.id, name: @location.name }
      }
    end
  rescue StandardError => e
    render json: { success: false, errors: [ e.message ] }, status: :unprocessable_entity
  end

  def create_producer_production
    ActiveRecord::Base.transaction do
      organization = Organization.find(params[:organization_id])

      # Create production
      @production = Production.new(
        name: params[:production_name],
        organization: organization
      )

      unless @production.save
        render json: { success: false, errors: @production.errors.full_messages }, status: :unprocessable_entity
        return
      end

      # Update session and mark as completed
      session[:pilot_producer_state][:production_id] = @production.id
      session[:pilot_producer_state][:production_name] = @production.name
      session[:pilot_producer_state][:completed] = true

      render json: {
        success: true,
        message: "Production created successfully",
        production: { id: @production.id, name: @production.name }
      }
    end
  rescue StandardError => e
    render json: { success: false, errors: [ e.message ] }, status: :unprocessable_entity
  end

  def create_producer_talent_pool
    ActiveRecord::Base.transaction do
      production = Production.find(params[:production_id])

      # Create talent pool
      @talent_pool = TalentPool.new(
        name: params[:talent_pool_name],
        production: production
      )

      unless @talent_pool.save
        render json: { success: false, errors: @talent_pool.errors.full_messages }, status: :unprocessable_entity
        return
      end

      # Create role
      @role = Role.new(
        name: params[:role_name],
        production: production
      )

      unless @role.save
        render json: { success: false, errors: @role.errors.full_messages }, status: :unprocessable_entity
        return
      end

      # Update session
      session[:pilot_producer_state][:talent_pool_id] = @talent_pool.id
      session[:pilot_producer_state][:talent_pool_name] = @talent_pool.name
      session[:pilot_producer_state][:role_id] = @role.id
      session[:pilot_producer_state][:role_name] = @role.name

      render json: {
        success: true,
        message: "Talent pool and role created successfully",
        talent_pool: { id: @talent_pool.id, name: @talent_pool.name },
        role: { id: @role.id, name: @role.name }
      }
    end
  rescue StandardError => e
    render json: { success: false, errors: [ e.message ] }, status: :unprocessable_entity
  end

  def create_producer_show
    ActiveRecord::Base.transaction do
      production = Production.find(params[:production_id])
      location = Location.find(params[:location_id])

      # Create show
      @show = Show.new(
        secondary_name: params[:show_name],
        date_and_time: params[:show_date_time],
        production: production,
        location: location
      )

      unless @show.save
        render json: { success: false, errors: @show.errors.full_messages }, status: :unprocessable_entity
        return
      end

      # Update session
      session[:pilot_producer_state][:show_id] = @show.id
      session[:pilot_producer_state][:show_name] = @show.secondary_name
      session[:pilot_producer_state][:completed] = true

      render json: {
        success: true,
        message: "Show created successfully",
        show: { id: @show.id, name: @show.secondary_name }
      }
    end
  rescue StandardError => e
    render json: { success: false, errors: [ e.message ] }, status: :unprocessable_entity
  end

  def create_producer_additional
    ActiveRecord::Base.transaction do
      organization = Organization.find(params[:organization_id])

      # Create additional producer user with random password
      @user = User.new(
        email_address: params[:email],
        password: SecureRandom.hex(16)
      )

      unless @user.save
        render json: { success: false, errors: @user.errors.full_messages }, status: :unprocessable_entity
        return
      end

      # Create person
      @person = Person.new(
        name: "#{params[:first_name]} #{params[:last_name]}".strip,
        email: params[:email],
        user: @user
      )

      raise ActiveRecord::Rollback unless @person.save

      # Associate person with organization
      @person.organizations << organization

      # Add as manager
      OrganizationRole.create!(
        user: @user,
        organization: organization,
        company_role: "manager"
      )

      # Create person invitation
      person_invitation = PersonInvitation.create!(
        email: @person.email,
        organization: organization
      )

      # Send invitation email
      Manage::PersonMailer.person_invitation(
        person_invitation,
        "You've been invited to join #{organization.name} on CocoScout",
        "Welcome to CocoScout!\n\n#{organization.name} is using CocoScout to manage its productions, auditions, and casting.\n\nTo get started, please click the link below to set a password and create your account."
      ).deliver_later

      # Store additional producers in session
      session[:pilot_producer_state][:additional_producers] ||= []
      session[:pilot_producer_state][:additional_producers] << @person.name

      render json: {
        success: true,
        message: "Additional producer added and invitation sent to #{@user.email_address}",
        user: { id: @user.id, email: @user.email_address },
        person: { id: @person.id, name: @person.name }
      }
    end
  rescue StandardError => e
    render json: { success: false, errors: [ e.message ] }, status: :unprocessable_entity
  end

  private

  def initialize_pilot_session
    session[:pilot_talent_state] ||= {}
    session[:pilot_producer_state] ||= {}
  end

  def require_superadmin
    return if Current.user&.superadmin?

    redirect_to root_path, alert: "Access denied"
  end
end
