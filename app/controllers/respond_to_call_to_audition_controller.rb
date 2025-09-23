class RespondToCallToAuditionController < ApplicationController
  allow_unauthenticated_access

  skip_before_action :set_current_production_company
  skip_before_action :set_current_production
  skip_before_action :require_current_production_company

  before_action :ensure_user_is_signed_in, only: [ :form, :submitform, :success ]

  before_action :get_call_to_audition_and_questions
  before_action :ensure_call_to_audition_is_open, only: [ :entry, :form, :submitform, :success ]

  def entry
    # If the user is already signed in, redirect them to the form
    if authenticated?
      redirect_to respond_to_call_to_audition_form_path(hex_code: @call_to_audition.hex_code), status: :see_other
      return
    end

    @user = User.new
  end

  def handlesignup
    # Get the email and show an error if it already exists
    normalized_email = user_params[:email_address].to_s.strip.downcase
    if User.exists?(email_address: normalized_email)
      @user = User.new(user_params)
      @user_exists_error = true
      render :entry, status: :unprocessable_entity
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
        redirect_to respond_to_call_to_audition_form_path(hex_code: @call_to_audition.hex_code), status: :see_other
      else
        render :entry, status: :unprocessable_entity
      end
    else
      render :entry, status: :unprocessable_entity
    end
  end

  def signin
  end

  def handlesignin
    user = User.find_by(email_address: params[:email_address].downcase)
    if user.nil?
      @user = User.new(email_address: params[:email_address])
      @authentication_error = true
      render :signin, status: :unprocessable_entity and return
    end

    # Try and authenticate the user.
    if user.authenticate(params[:password])

      # Create the associated person if it doesn't exist
      person = Person.find_by(email: user.email_address)
      if person.nil?
        person = Person.new(email: user.email_address, name: user.email_address.split("@").first, user: user)
        person.save!
      else
        # The person exists, so just make sure their user and person are tied to each other
        person.user = user
        person.save! if person.changed?
      end

      # Sign the user in
      start_new_session_for user

      # Redirect to the form for this call to audition
      redirect_to respond_to_call_to_audition_form_path(hex_code: @call_to_audition.hex_code), status: :see_other
    else
      @user = User.new(email_address: params[:email_address])
      @authentication_error = true
      render :signin, status: :unprocessable_entity and return
    end
  end

  def form
    # If the user isn't signed in, redirect them to the entry
    unless authenticated?
      redirect_to respond_to_call_to_audition_path, status: :see_other
      return
    end

    @person = Current.user.person

    # First we'll check if they've already responded to this call to audition
    if @call_to_audition.audition_requests.exists?(person: Current.user.person)

      @audition_request = @call_to_audition.audition_requests.find_by(person: Current.user.person)
      @answers = {}
      @questions.each do |question|
        answer = @audition_request.answers.find_by(question: question)
        @answers["#{question.id}"] = answer.value if answer
      end

    else
      # They haven't responded yet, so we'll let them create a new response
      @audition_request = AuditionRequest.new

      # Empty answers hash
      @answers = {}
      @questions.each do |question|
        @answers["#{question.id}"] = ""
      end

    end
  end

  def submitform
    @person = Current.user.person

    # We may be updating an existing response, so check for that first
    if @call_to_audition.audition_requests.exists?(person: Current.user.person)

      # Get the person and audition request
      @audition_request = @call_to_audition.audition_requests.find_by(person: @person)

      # Update the answers
      @answers = {}
      params[:question].each do |id, keyValue|
        answer = @audition_request.answers.find_or_initialize_by(question: Question.find(id))
        answer.value = keyValue
        answer.save!
        @answers["#{id}"] = answer.value
      end

    else

      # It's a new request, so instantiate the objects
      @audition_request = AuditionRequest.new(person: @person)
      @audition_request.call_to_audition = @call_to_audition

      # Loop through the questions and store the answers
      @answers = {}
      params[:question].each do |question|
        answer = @audition_request.answers.build
        answer.question = Question.find question.first
        answer.value = question.last
        @answers["#{answer.question.id}"] = answer.value
      end

    end

    if @audition_request.valid?

  # Update the person with any updated details
  person_params = params.require(:audition_request).permit(person: [ :name, :pronouns, :socials, :resume, :headshot ])
      @person.assign_attributes(person_params[:person])

      if @person.valid?
        @person.save!
      else
        @person.reload
        @update_person_error = true
        render :form, status: :unprocessable_entity and return
      end

      # Save the audition request and redirect to the success page
      @audition_request.save!
      redirect_to respond_to_call_to_audition_success_path(hex_code: @call_to_audition.hex_code), status: :see_other
    else
      render :form
    end
  end

  def success
  end

  def inactive
    if @call_to_audition.timeline_status == :open && params[:force].blank?
      redirect_to respond_to_call_to_audition_path(hex_code: @call_to_audition.hex_code), status: :see_other
    end
  end

  def get_call_to_audition_and_questions
    @call_to_audition = CallToAudition.find_by(hex_code: params[:hex_code].upcase)
    @questions = @call_to_audition.questions.order(:created_at) if @call_to_audition.present? # TODO Change this to be re-arrangeable

    if @call_to_audition.nil?
      redirect_to root_path, alert: "Invalid call to audition"
      return
    end

    @production = @call_to_audition.production
  end

  def ensure_call_to_audition_is_open
    unless @call_to_audition.timeline_status == :open
      redirect_to respond_to_call_to_audition_inactive_path(hex_code: @call_to_audition.hex_code), status: :see_other
    end
  end

  def ensure_user_is_signed_in
    unless authenticated?
      redirect_to respond_to_call_to_audition_path, status: :see_other
    end
  end
  private

  def user_params
    params.require(:user).permit(:email_address, :password)
  end
end
