class My::SubmitAuditionRequestController < ApplicationController
  allow_unauthenticated_access only: [ :entry, :inactive ]

  skip_before_action :show_my_sidebar

  before_action :ensure_user_is_signed_in, only: [ :form, :submitform, :success ]
  before_action :get_audition_cycle_and_questions
  before_action :ensure_audition_cycle_is_open, only: [ :entry, :form, :submitform, :success ]

  def entry
    # If the user is already signed in, redirect them to the form
    if authenticated?
      redirect_to my_submit_audition_request_form_path(token: @audition_cycle.token), status: :see_other
      return
    end

    @user = User.new

    # Set the return_to path in case we sign up or sign in
    session[:return_to] = my_submit_audition_request_form_path(token: @audition_cycle.token)
  end

  def form
    # If the user isn't signed in, redirect them to the entry
    unless authenticated?
      redirect_to submit_audition_request_path, status: :see_other
      return
    end

    @person = Current.user.person

    # Load shows for availability section if enabled
    if @audition_cycle.include_availability_section
      @production = @audition_cycle.production
      @shows = @production.shows.where("date_and_time >= ?", Time.current).order(:date_and_time)

      # Filter by show ids if specified
      if @audition_cycle.availability_show_ids.present?
        @shows = @shows.where(id: @audition_cycle.availability_show_ids)
      end

      # Load existing availability data
      @availability = {}
      ShowAvailability.where(available_entity: @person, show_id: @shows.pluck(:id)).each do |show_availability|
        @availability["#{show_availability.show_id}"] = show_availability.status.to_s
      end
    end

    # First we'll check if they've already responded to this audition cycle
    if @audition_cycle.audition_requests.exists?(requestable: Current.user.person)

      @audition_request = @audition_cycle.audition_requests.find_by(requestable: Current.user.person)
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

    # Associate the person with the organization if not already
    organization = @audition_cycle.production.organization
    unless @person.organizations.include?(organization)
      @person.organizations << organization
    end

    # We may be updating an existing response, so check for that first
    if @audition_cycle.audition_requests.exists?(requestable: Current.user.person)

      # Get the person and audition request
      @audition_request = @audition_cycle.audition_requests.find_by(requestable: @person)

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
      @audition_request = AuditionRequest.new(requestable: @person)
      @audition_request.audition_cycle = @audition_cycle

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

    # Validate required availability if enabled
    @missing_availability = false
    if @audition_cycle.include_availability_section && @audition_cycle.require_all_availability
      # Load shows to check (only future dates)
      @shows = @production.shows.where("date_and_time >= ?", Time.current).order(:date_and_time)
      if @audition_cycle.availability_show_ids.present?
        @shows = @shows.where(id: @audition_cycle.availability_show_ids)
      end

      # Check if all shows have a response
      @shows.each do |show|
        if params[:availability].blank? || params[:availability]["#{show.id}"].blank?
          @missing_availability = true
          break
        end
      end
    end

    # Validate and save
    if @missing_required_questions.any? || @missing_availability
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

      # Save availability data if included
      if @audition_cycle.include_availability_section && params[:availability].present?
        params[:availability].each do |show_id, status|
          next if status.blank?

          show_availability = ShowAvailability.find_or_initialize_by(
            person: @person,
            show_id: show_id
          )

          # Map the status values to the enum
          show_availability.status = if status == "available"
            :available
          elsif status == "unavailable"
            :unavailable
          else
            :unset
          end
          show_availability.save!
        end
      end

      redirect_to my_submit_audition_request_success_path(token: @audition_cycle.token), status: :see_other
    else
      render :form
    end
  end

  def success
  end

  def inactive
    if @audition_cycle.timeline_status == :open && @audition_cycle.form_reviewed && params[:force].blank?
      redirect_to submit_audition_request_path(token: @audition_cycle.token), status: :see_other
    end
  end

  def get_audition_cycle_and_questions
    @audition_cycle = AuditionCycle.find_by(token: params[:token].upcase)
    @questions = @audition_cycle.questions.order(:position) if @audition_cycle.present?

    if @audition_cycle.nil?
      redirect_to root_path, alert: "Invalid audition cycle"
      return
    end

    @production = @audition_cycle.production
  end

  def ensure_audition_cycle_is_open
    unless @audition_cycle.timeline_status == :open && @audition_cycle.form_reviewed
      redirect_to my_submit_audition_request_inactive_path(token: @audition_cycle.token), status: :see_other
    end
  end

  def ensure_user_is_signed_in
    unless authenticated?
      redirect_to submit_audition_request_path, status: :see_other
    end
  end

  private

  def person_params
    params.require(:audition_request).permit(:video_url, person: [ :name, :pronouns, :resume, :headshot, socials_attributes: [ :id, :platform, :handle, :_destroy ] ])
  end
end
