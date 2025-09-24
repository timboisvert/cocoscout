class AuthController < ApplicationController
  allow_unauthenticated_access only: %i[ signup handle_signup signin handle_signin password handle_password ]
  rate_limit to: 10, within: 3.minutes, only: :handle_signin, with: -> { redirect_to signin_path, alert: "Try again later." }

  # before_action :set_user_by_token, only: %i[ edit_password handle_edit_password ]

  skip_before_action :show_my_sidebar

  def signup
    @user = User.new
  end

  def handle_signup
    # Get the email and show an error if it already exists
    normalized_email = user_params[:email_address].to_s.strip.downcase
    if User.exists?(email_address: normalized_email)
      @user = User.new(user_params)
      @user_exists_error = true
      @email_address = normalized_email
      render :signin, status: :unprocessable_entity
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
        redirect_to(session.delete(:return_to) || my_dashboard_path) and return
      else
        render :signup, status: :unprocessable_entity
      end
    else
      render :signup, status: :unprocessable_entity
    end
  end

  def signin
    @user = User.new
  end

  def handle_signin
    if user = User.authenticate_by(params.permit(:email_address, :password))

      # Make sure we have a person for this user
      if user.person.nil?
        person = Person.find_by(email: user.email_address)
        if person
          person.user = user
          person.save!
        else
          user.create_person(email: user.email_address, name: user.email_address.split("@").first)
        end
      end

      # Continue signing them in.
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

  def password
  end

  def handle_password
    if user = User.find_by(email_address: params[:email_address])
      # PasswordsMailer.reset(user).deliver_later
    end

    redirect_to signin_path, notice: "Password reset instructions sent (if user with that email address exists)."
  end

  # def edit_password
  # end

  # def handle_edit_password
  #   if @user.update(params.permit(:password))
  #     redirect_to new_session_path, notice: "Password has been reset."
  #   else
  #     redirect_to edit_password_path(params[:token]), alert: "Passwords did not match."
  #   end
  # end


  private

  def user_params
    params.require(:user).permit(:email_address, :password)
  end

  # def set_user_by_token
  #   @user = User.find_by_password_reset_token!(params[:token])
  # rescue ActiveSupport::MessageVerifier::InvalidSignature
  #   redirect_to new_password_path, alert: "Password reset link is invalid or has expired."
  # end
end
