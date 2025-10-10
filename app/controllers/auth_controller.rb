class AuthController < ApplicationController
  allow_unauthenticated_access only: %i[ signup handle_signup signin handle_signin password handle_password reset handle_reset]
  rate_limit to: 10, within: 3.minutes, only: :handle_signin, with: -> { redirect_to signin_path, alert: "Try again later." }

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
        AuthMailer.signup(@user).deliver_later
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

    if session[:password_reset_instructions_sent] == true
      session.delete(:password_reset_instructions_sent)
      @password_reset_instructions_sent = true
    end

    if session[:password_successfully_reset] == true
      session.delete(:password_successfully_reset)
      @password_successfully_reset = true
    end
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
    if session[:reset_link_expired_or_invalid] == true
      session.delete(:reset_link_expired_or_invalid)
      @reset_link_expired_or_invalid = true
    end
  end

  def handle_password
    if user = User.find_by(email_address: params[:email_address])
      token = SecureRandom.urlsafe_base64(32)
      user.update(password_reset_token: token, password_reset_sent_at: Time.current)
      AuthMailer.password(user, token).deliver_later
    end
    session[:password_reset_instructions_sent] = true
    redirect_to signin_path and return
  end

  def reset
    @user = User.find_by(password_reset_token: params[:token])
    if @user.nil? || @user.password_reset_sent_at < 2.hours.ago
      session[:reset_link_expired_or_invalid] = true
      redirect_to password_path and return
    end
  end

  def handle_reset
    @user = User.find_by(password_reset_token: params[:token])
    if @user.nil? || @user.password_reset_sent_at < 2.hours.ago
      session[:reset_link_expired_or_invalid] = true
      redirect_to password_path and return
    end
    if @user.update(password: params[:password], password_reset_token: nil, password_reset_sent_at: nil)
      session[:password_successfully_reset] = true
      redirect_to signin_path and return
    else
      @password_unsuccessfully_reset = true
      render :reset
    end
  end

  private

  def user_params
    params.require(:user).permit(:email_address, :password)
  end
end
