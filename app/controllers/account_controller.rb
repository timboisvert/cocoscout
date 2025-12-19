# frozen_string_literal: true

class AccountController < ApplicationController
  skip_before_action :show_my_sidebar
  before_action :set_account_sidebar
  before_action :set_profile, only: [ :set_default_profile, :archive_profile ]

  # Rate limit: can only change email once per 24 hours
  EMAIL_CHANGE_COOLDOWN = 24.hours

  def show
    @person = Current.user.person
  end

  def update
    if Current.user.update(user_params)
      redirect_to account_path, notice: "Account updated successfully."
    else
      render :show, status: :unprocessable_entity
    end
  end

  def update_email
    new_email = params[:email_address]&.strip&.downcase

    # Check rate limit
    if Current.user.email_changed_at.present? && Current.user.email_changed_at > EMAIL_CHANGE_COOLDOWN.ago
      render json: { success: false, error: "You've changed your email too recently. Please try again later." }, status: :unprocessable_entity
      return
    end

    # Check if email is same as current
    if new_email == Current.user.email_address
      render json: { success: false, error: "This is already your email address." }, status: :unprocessable_entity
      return
    end

    # Check if email already exists
    if User.where.not(id: Current.user.id).exists?(email_address: new_email)
      render json: { success: false, error: "An account with this email address already exists." }, status: :unprocessable_entity
      return
    end

    # Get profile IDs to update
    profile_ids_to_update = params[:profile_ids] || []

    ActiveRecord::Base.transaction do
      old_email = Current.user.email_address

      # Update user email
      Current.user.update!(email_address: new_email, email_changed_at: Time.current)

      # Update selected profile emails
      if profile_ids_to_update.any?
        Current.user.people.where(id: profile_ids_to_update).each do |person|
          person.update!(email: new_email) if person.email == old_email
        end
      end
    end

    render json: { success: true, message: "Email updated successfully." }
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
  end

  def profiles
    @profiles = Current.user.people.active.order(:created_at)
    @default_profile = Current.user.default_person
    @groups = Current.user.person&.groups&.active&.includes(:group_memberships) || []
  end

  def create_profile
    @profile = Person.new(profile_params)
    @profile.user = Current.user
    @profile.email = Current.user.email_address if @profile.email.blank?

    if @profile.save
      if params[:set_as_default] == "1" || Current.user.people.active.count == 1
        Current.user.set_default_person!(@profile)
      end
      redirect_to account_profiles_path, notice: "Profile created successfully."
    else
      @profiles = Current.user.people.active.order(:created_at)
      @default_profile = Current.user.default_person
      render :profiles, status: :unprocessable_entity
    end
  end

  def set_default_profile
    Current.user.set_default_person!(@profile)
    redirect_to account_profiles_path, notice: "\"#{@profile.name}\" is now your default profile."
  end

  def archive_profile
    if @profile.default_profile? && Current.user.people.active.count == 1
      redirect_to account_profiles_path, alert: "You cannot archive your only profile."
      return
    end

    if @profile.default_profile?
      new_default = Current.user.people.active.where.not(id: @profile.id).order(:created_at).first
      Current.user.update!(default_person: new_default)
    end

    @profile.archive!
    redirect_to account_profiles_path, notice: "Profile archived."
  end

  def notifications
  end

  def update_notifications
    # TODO: Handle notification preferences
    redirect_to account_notifications_path, notice: "Notification preferences updated."
  end

  def billing
  end

  private

  def set_account_sidebar
    @show_account_sidebar = true
  end

  def set_profile
    @profile = Current.user.people.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:email_address)
  end

  def profile_params
    params.require(:person).permit(:name, :email, :pronouns)
  end
end
