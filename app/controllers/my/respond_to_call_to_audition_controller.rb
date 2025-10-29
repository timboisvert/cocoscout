class My::RespondToCallToAuditionController < ApplicationController
  allow_unauthenticated_access only: [ :entry, :inactive ]

  skip_before_action :show_my_sidebar

  before_action :ensure_user_is_signed_in, only: [ :form, :submitform, :success ]
  before_action :get_call_to_audition_and_questions
  before_action :ensure_call_to_audition_is_open, only: [ :entry, :form, :submitform, :success ]

  def entry
    # If the user is already signed in, redirect them to the form
    if authenticated?
      redirect_to my_respond_to_call_to_audition_form_path(token: @call_to_audition.token), status: :see_other
      return
    end

    @user = User.new

    # Set the return_to path in case we sign up or sign in
    session[:return_to] = my_respond_to_call_to_audition_form_path(token: @call_to_audition.token)
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

    # Associate the person with the production company if not already
    production_company = @call_to_audition.production.production_company
    unless @person.production_companies.include?(production_company)
      @person.production_companies << production_company
    end

    # We may be updating an existing response, so check for that first
    if @call_to_audition.audition_requests.exists?(person: Current.user.person)

      # Get the person and audition request
      @audition_request = @call_to_audition.audition_requests.find_by(person: @person)

      # Update the answers
      @answers = {}
      if params[:question]
        params[:question].each do |id, keyValue|
          answer = @audition_request.answers.find_or_initialize_by(question: Question.find(id))
          answer.value = keyValue
          answer.save!
          @answers["#{id}"] = answer.value
        end
      end

    else

      # It's a new request, so instantiate the objects
      @audition_request = AuditionRequest.new(person: @person)
      @audition_request.call_to_audition = @call_to_audition

      # Loop through the questions and store the answers
      @answers = {}
      if params[:question]
        params[:question].each do |question|
          answer = @audition_request.answers.build
          answer.question = Question.find question.first
          answer.value = question.last
          @answers["#{answer.question.id}"] = answer.value
        end
      end

    end

    # Assign the submitted attributes to the audition request
    @audition_request.assign_attributes(person_params.except(:person))

    # Validate required questions
    @missing_required_questions = []
    @questions.select(&:required).each do |question|
      answer_value = @answers["#{question.id}"]
      if answer_value.blank? || (answer_value.is_a?(Hash) && answer_value.values.all?(&:blank?))
        @missing_required_questions << question
      end
    end

    # Validate and save
    if @missing_required_questions.any?
      render :form, status: :unprocessable_entity
    elsif @audition_request.valid?

      # Update the person with any updated details
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
      redirect_to my_respond_to_call_to_audition_success_path(token: @call_to_audition.token), status: :see_other
    else
      render :form
    end
  end

  def success
  end

  def inactive
    if @call_to_audition.timeline_status == :open && params[:force].blank?
      redirect_to respond_to_call_to_audition_path(token: @call_to_audition.token), status: :see_other
    end
  end

  def get_call_to_audition_and_questions
    @call_to_audition = CallToAudition.find_by(token: params[:token].upcase)
    @questions = @call_to_audition.questions.order(:position) if @call_to_audition.present?

    if @call_to_audition.nil?
      redirect_to root_path, alert: "Invalid call to audition"
      return
    end

    @production = @call_to_audition.production
  end

  def ensure_call_to_audition_is_open
    unless @call_to_audition.timeline_status == :open
      redirect_to my_respond_to_call_to_audition_inactive_path(token: @call_to_audition.token), status: :see_other
    end
  end

  def ensure_user_is_signed_in
    unless authenticated?
      redirect_to respond_to_call_to_audition_path, status: :see_other
    end
  end

  private

  def person_params
    params.require(:audition_request).permit(:video_url, person: [ :name, :pronouns, :resume, :headshot, socials_attributes: [ :id, :platform, :handle, :_destroy ] ])
  end
end
