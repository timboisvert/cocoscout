# frozen_string_literal: true

module My
  class ProfilesController < ApplicationController
    before_action :set_profile, only: [ :edit, :update, :set_default, :archive ]

    def index
      @profiles = Current.user.people.active.order(:created_at)
      @default_profile = Current.user.default_person
    end

    def new
      @profile = Person.new
      @is_first_profile = Current.user.people.active.count == 0
    end

    def create
      @profile = Person.new(profile_params)
      @profile.user = Current.user
      @profile.email = Current.user.email_address if @profile.email.blank?

      if @profile.save
        # Set as default if requested or if this is the user's first profile
        if params[:set_as_default] == "1" || Current.user.people.active.count == 1
          Current.user.set_default_person!(@profile)
        end

        redirect_to my_profiles_path, notice: "Profile created successfully."
      else
        @is_first_profile = Current.user.people.active.count == 0
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @profile.update(profile_params)
        # Set as default if requested
        if params[:set_as_default] == "1"
          Current.user.set_default_person!(@profile)
        end

        redirect_to my_profiles_path, notice: "Profile updated successfully."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def set_default
      Current.user.set_default_person!(@profile)
      redirect_to my_profiles_path, notice: "\"#{@profile.name}\" is now your default profile."
    end

    def archive
      # Cannot archive the default profile if it's the only one
      if @profile.default_profile? && Current.user.people.active.count == 1
        redirect_to my_profiles_path, alert: "You cannot archive your only profile."
        return
      end

      # If archiving the default profile, set a new default
      if @profile.default_profile?
        new_default = Current.user.people.active.where.not(id: @profile.id).order(:created_at).first
        Current.user.update!(default_person: new_default)
      end

      @profile.archive!
      redirect_to my_profiles_path, notice: "Profile archived."
    end

    private

    def set_profile
      @profile = Current.user.people.find(params[:id])
    end

    def profile_params
      params.require(:person).permit(:name, :email, :pronouns, :bio, :public_key, :public_profile_enabled)
    end
  end
end
