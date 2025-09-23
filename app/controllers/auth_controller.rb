class AuthController < ApplicationController
  allow_unauthenticated_access only: %i[ signup handle_signup signin handle_signin ]
  rate_limit to: 10, within: 3.minutes, only: :handle_signin, with: -> { redirect_to signin_path, alert: "Try again later." }

  skip_before_action :show_app_sidebar

  def signup
    @user = User.new
  end

  def handle_signup
    # Get the email and show an error if it already exists
    normalized_email = user_params[:email_address].to_s.strip.downcase
    if User.exists?(email_address: normalized_email)
      @user = User.new(user_params)
      @user_exists_error = true
      render :signup, status: :unprocessable_entity
      return
    end

    # The user doesn't exist, so create it
    @user = User.new(user_params)
    if @user.save

      # Create the associated person if it doesn't exist
      person = Person.find_by(email: @user.email_address)
      if person.nil?
        person = Person.new(email: @user.email_address, name: @user.email_address.split("@").first, user: @user)
      else
        # The person exists, so just make sure their user and person are tied to each other
        person.user = @user
      end
      person.save!

      # The user has been created, so log them in
      if User.authenticate_by(user_params.slice(:email_address, :password))
        start_new_session_for @user
        redirect_to manage_path, notice: "User was successfully created."
      else
        render :signup, status: :unprocessable_entity
      end
    else
      render :signup, status: :unprocessable_entity
    end
  end

  def signin
  end

  def handle_signin
    if user = User.authenticate_by(params.permit(:email_address, :password))
      start_new_session_for user
      redirect_to(session.delete(:return_to) || my_dashboard_path) and return
    else
      @error = true
      render :signin, status: :unprocessable_entity
    end
  end

  def signout
    terminate_session
    redirect_to my_dashboard_path
  end

  private

  def user_params
    params.require(:user).permit(:email_address, :password)
  end
end
