# frozen_string_literal: true

module My
  class ProfilesController < ApplicationController
    before_action :require_authentication

    # Profiles are listed under Account; this path is only the form's home.
    def index
      redirect_to account_profiles_path
    end

    def new
      @profile = Person.new
    end

    def create
      @profile = Person.new(profile_params)
      @profile.user = Current.user
      @profile.email ||= Current.user.email_address

      if @profile.save
        set_default_if_requested
        redirect_to account_profiles_path, notice: "Profile '#{@profile.name}' created successfully!"
      else
        render :new, status: :unprocessable_content
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
