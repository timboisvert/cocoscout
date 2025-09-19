class UsersController < ApplicationController
  allow_unauthenticated_access only: %i[signup create]

  def signup
    @user = User.new
  end

  def create
    # Get the email and show an error if it already exists
    normalized_email = user_params[:email].to_s.strip.downcase
    if User.exists?(email_address: normalized_email)
      @user = User.new(user_params)
      @user.errors.add(:email_address, "has already been taken")
      render :signup, status: :unprocessable_entity
      return
    end

    # The user doesn't exist, so create it
    @user = User.new(user_params)
    if @user.save

      # Create the associated person if it doesn't exist
      person = Person.find_by(email: @user.email_address)
      if person.nil?
        person = Person.new(email: @user.email_address, stage_name: @user.email_address.split("@").first, user: @user)
      else
        # The person exists, so just make sure their user and person are tied to each other
        person.user = @user
      end
      person.save!

      # The user has been created, so log them in
      if User.authenticate_by(user_params.slice(:email_address, :password))
        start_new_session_for @user
        redirect_to dashboard_path, notice: "User was successfully created."
      else
        render :signup, status: :unprocessable_entity
      end
    else
      render :signup, status: :unprocessable_entity
    end
  end

  private

  def user_params
    # Accept both :email and :email_address for flexibility
    p = params.require(:user).permit(:email, :email_address, :password)
    p[:email_address] = p.delete(:email) if p[:email]
    p
  end
end
