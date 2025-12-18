# frozen_string_literal: true

class AccountController < ApplicationController
  skip_before_action :show_my_sidebar
  before_action :set_account_sidebar
  before_action :set_profile, only: [:set_default_profile, :archive_profile]

  def show
  end

  def update
    if Current.user.update(user_params)
      redirect_to account_path, notice: "Account updated successfully."
    else
      render :show, status: :unprocessable_entity
    end
  end

  def profiles
    @profiles = Current.user.people.active.order(:created_at)
    @default_profile = Current.user.default_person
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
