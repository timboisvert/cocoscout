# frozen_string_literal: true

module My
  class ProfilesController < ApplicationController
    before_action :require_authentication

    def index
      @profiles = Current.user.people.order(:name)
    end

    def new
      @profile = Person.new
    end

    def create
      @profile = Person.new(profile_params)
      @profile.user = Current.user
      @profile.email ||= Current.user.email_address
      @profile.profile_welcomed_at = Time.current  # Skip welcome screen for additional profiles

      if @profile.save
        set_default_if_requested
        redirect_to account_profiles_path, notice: "Profile '#{@profile.name}' created successfully!"
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def profile_params
      params.require(:person).permit(:name, :pronouns, :email, :bio)
    end

    def set_default_if_requested
      return unless params[:set_as_default] == "1"

      Current.user.update!(default_person: @profile)
    end
  end
end
