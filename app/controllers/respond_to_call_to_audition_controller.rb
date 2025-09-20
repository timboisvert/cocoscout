class RespondToCallToAuditionController < ApplicationController
  allow_unauthenticated_access only: [ :entry ]

  before_action :get_call_to_audition_and_questions
  before_action :ensure_call_to_audition_is_open, only: [ :new, :create, :success ]

  # Use the public facing layout
  layout "public_facing"

  def entry
  end

  def new
    # First we'll check if they've already responded to this call to audition
    if cookies.signed["#{@call_to_audition.hex_code}"]

      # The user has already responded, so look up their Person object and Audution Request
      @person = Person.find_by(email: cookies.signed["#{@call_to_audition.hex_code}"])

      if @person.nil?
        cookies.delete "#{@call_to_audition.hex_code}"
        redirect_to respond_to_call_to_audition_form_path(hex_code: @call_to_audition.hex_code), status: :see_other
      else
        @audition_request = @call_to_audition.audition_requests.find_by(person: @person)

        if @audition_request.nil?
          cookies.delete "#{@call_to_audition.hex_code}"
          redirect_to respond_to_call_to_audition_form_path(hex_code: @call_to_audition.hex_code), status: :see_other
        else
          @answers = {}
          @questions.each do |question|
            answer = @audition_request.answers.find_by(question: question)
            @answers["#{question.id}"] = answer.value if answer
          end

        end
      end

    else
      # They haven't responded yet, so we'll let them create a new response
      @audition_request = AuditionRequest.new
      @person = @audition_request.build_person

      # Empty answers hash
      @answers = {}
      @questions.each do |question|
        @answers["#{question.id}"] = ""
      end

    end
  end

  def create
    # Strong parameters for the person
    person_params = params.require(:audition_request).permit(person: [ :stage_name, :email, :pronouns, :socials, :resume, :headshot, :questions ])

    # We may be updating an existing response, so check for that first
    if cookies.signed["#{@call_to_audition.hex_code}"]

      # Get the person and audition request
      @person = Person.find_by(email: cookies.signed["#{@call_to_audition.hex_code}"])
      @audition_request = @call_to_audition.audition_requests.find_by(person: @person)

      # Update the person with the new details
      @person.assign_attributes(person_params[:person])

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
      @audition_request = AuditionRequest.new
      @audition_request.call_to_audition = @call_to_audition
      @person = @audition_request.build_person(person_params[:person])

      # Loop through the questions and store the answers
      @answers = {}
      params[:question].each do |question|
        answer = @audition_request.answers.build
        answer.question = Question.find question.first
        answer.value = question.last
        @answers["#{answer.question.id}"] = answer.value
      end

    end

    if @audition_request.valid? && @person.valid?

      # Check to ensure this is a unique person for this call to audition
      # If it's not unique, update the existing person
      existing_person = Person.find_by(email: @person.email)
      if existing_person
        existing_person.assign_attributes(@person.attributes.except("id", "created_at", "updated_at"))
        @person = existing_person

        # Add the headshot and resume if they've been passed in
        @person.headshot = person_params[:person][:headshot] if person_params[:person][:headshot].present?
        @person.resume = person_params[:person][:resume] if person_params[:person][:resume].present?

        # Check to see if this person has already submitted an audition request for this call to audition
        existing_audition_request = @call_to_audition.audition_requests.find_by(person: @person)
        if existing_audition_request

          # Update the existing audition request with any new details
          existing_audition_request.assign_attributes(@audition_request.attributes.except("id", "created_at", "updated_at"))
          @audition_request = existing_audition_request

          # Put the new answers onto the existing audition request
          new_answers = []
          @answers.each do |answer|
            new_answer = @audition_request.answers.build
            new_answer.audition_request = @audition_request
            new_answer.question = Question.find(answer.first)
            new_answer.value = answer.last
            new_answers << new_answer
          end
          @audition_request.answers = new_answers
        end

        # Make sure audition request points to the proper user if any changes have been made
        @audition_request.person = @person

      end

      @person.save!
      @audition_request.save!

      cookies.signed["#{@call_to_audition.hex_code}"] = { value: @person.email, expires: 5.years.from_now }
      redirect_to respond_to_call_to_audition_success_path(hex_code: @call_to_audition.hex_code), status: :see_other
    else
      render :new
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
end
