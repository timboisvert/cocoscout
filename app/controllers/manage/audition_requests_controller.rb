# frozen_string_literal: true

module Manage
  class AuditionRequestsController < Manage::ManageController
    before_action :set_production
    before_action :check_production_access
    before_action :set_audition_cycle
    before_action :set_audition_request, only: %i[show edit_answers edit_video update destroy update_audition_session_availability cast_vote votes]
    before_action :ensure_user_is_manager, except: %i[index show cast_vote votes]
    before_action :ensure_audition_cycle_active, only: %i[edit_answers edit_video update update_audition_session_availability cast_vote]

    def index
      # Redirect to audition cycle show page if archived
      unless @audition_cycle.active
        redirect_to manage_production_signups_auditions_cycle_path(@production, @audition_cycle)
        return
      end

      @audition_requests = @audition_cycle.audition_requests.order(:created_at)
    end

    def show
      # Get the requestable (Person or Group)
      @requestable = @audition_request.requestable

      # Get the answers
      @answers = @audition_request.answers.includes(:question)

      # Get all votes for this request
      @votes = @audition_request.audition_request_votes.includes(user: :default_person)
      @current_user_vote = @audition_request.vote_for(Current.user)

      # Load availability data if enabled
      if @audition_cycle.include_availability_section
        @shows = @production.shows.where("date_and_time >= ?", Time.current).order(:date_and_time)
        @shows = @shows.where(id: @audition_cycle.availability_show_ids) if @audition_cycle.availability_show_ids.present?

        @availability = {}
        @show_availabilities = {}
        ShowAvailability.where(available_entity: @requestable, show_id: @shows.pluck(:id)).each do |show_availability|
          @availability[show_availability.show_id.to_s] = show_availability.status.to_s
          @show_availabilities[show_availability.show_id] = show_availability
        end
      end

      # Load audition session availability data if enabled
      if @audition_cycle.include_audition_availability_section
        @audition_sessions = @audition_cycle.audition_sessions.where("start_at >= ?", Time.current).order(:start_at)

        @audition_availability = {}
        AuditionSessionAvailability.where(available_entity: @requestable, audition_session_id: @audition_sessions.pluck(:id)).each do |session_availability|
          @audition_availability[session_availability.audition_session_id.to_s] = session_availability.status.to_s
        end
      end
    end

    def new
      @audition_request = @audition_cycle.audition_requests.new
    end

    def create
      @audition_request = @audition_cycle.audition_requests.new(audition_request_params)
      @audition_request.audition_cycle = @audition_cycle

      if @audition_request.save
        redirect_to manage_production_signups_auditions_cycle_requests_path(@production, @audition_cycle),
                    notice: "Sign-up was successfully created"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit_answers
      @questions = @audition_request.audition_cycle.questions.order(:position) if @audition_cycle.present?

      @answers = {}
      @questions.each do |question|
        answer = @audition_request.answers.find_by(question: question)
        @answers[question.id.to_s] = answer.value if answer
      end
    end

    def edit_video; end

    def update
      @questions = @audition_request.audition_cycle.questions.order(:position) if @audition_cycle.present?
      @answers = {}
      params[:question]&.each do |id, keyValue|
        answer = @audition_request.answers.find_or_initialize_by(question: Question.find(id))
        answer.value = keyValue
        answer.save!
        @answers[id.to_s] = answer.value
      end

      @audition_request.assign_attributes(audition_request_params) if params[:audition_request]

      # Validate required questions
      @missing_required_questions = []
      @questions.select(&:required).each do |question|
        answer_value = @answers[question.id.to_s]
        if answer_value.blank? || (answer_value.is_a?(Hash) && answer_value.values.all?(&:blank?))
          @missing_required_questions << question
        end
      end

      if @missing_required_questions.any?
        render :edit_answers, status: :unprocessable_entity
      elsif @audition_request.valid?
        @audition_request.save!
        redirect_to manage_production_signups_auditions_cycle_request_path(@production, @audition_cycle, @audition_request),
                    notice: "Sign-up successfully updated", status: :see_other
      else
        render :edit_answers, status: :unprocessable_entity
      end
    end

    def destroy
      @audition_request.destroy!
      redirect_to manage_production_signups_auditions_cycle_requests_path(@production, @audition_cycle),
                  notice: "Sign-up successfully deleted", status: :see_other
    end

    def cast_vote
      vote = @audition_request.audition_request_votes.find_or_initialize_by(user: Current.user)
      vote.vote = params[:vote] if params[:vote].present?
      vote.comment = params[:comment] if params.key?(:comment)

      # Can only save a comment if we have a vote (vote is required)
      if vote.vote.blank? && vote.new_record?
        respond_to do |format|
          redirect_url = manage_production_signups_auditions_cycle_request_path(@production, @audition_cycle, @audition_request)
          redirect_url += "?tab=#{params[:tab]}" if params[:tab].present?
          format.html { redirect_back_or_to redirect_url, alert: "Please cast a vote before adding a comment" }
          format.json { render json: { success: false, errors: [ "Please cast a vote first" ] }, status: :unprocessable_entity }
        end
        return
      end

      if vote.save
        respond_to do |format|
          redirect_url = manage_production_signups_auditions_cycle_request_path(@production, @audition_cycle, @audition_request)
          redirect_url += "?tab=#{params[:tab]}" if params[:tab].present?
          format.html { redirect_back_or_to redirect_url, notice: "Vote recorded" }
          format.json { render json: { success: true, vote: vote.vote, comment: vote.comment } }
        end
      else
        respond_to do |format|
          redirect_url = manage_production_signups_auditions_cycle_request_path(@production, @audition_cycle, @audition_request)
          redirect_url += "?tab=#{params[:tab]}" if params[:tab].present?
          format.html { redirect_back_or_to redirect_url, alert: vote.errors.full_messages.join(", ") }
          format.json { render json: { success: false, errors: vote.errors.full_messages }, status: :unprocessable_entity }
        end
      end
    end

    def votes
      @votes = @audition_request.audition_request_votes.includes(user: :default_person).order(created_at: :desc)
    end

    def update_audition_session_availability
      requestable = @audition_request.requestable

      # Extract session_id from params - it could be in availability_session_id or embedded in the key
      session_id = params[:availability_session_id]

      # If not found, look for the availability_X parameter
      if session_id.blank?
        availability_param = params.keys.find { |k| k.to_s.start_with?("availability_") && k.to_s != "availability_session_id" }
        session_id = availability_param.to_s.sub("availability_", "") if availability_param
      end

      status = params["availability_#{session_id}"]
      session = AuditionSession.find(session_id)
      availability = AuditionSessionAvailability.find_or_initialize_by(
        available_entity: requestable,
        audition_session: session
      )

      availability.status = status
      if availability.save
        render json: { status: availability.status }
      else
        render json: { error: availability.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end
    end

    private

    def set_production
      unless Current.organization
        redirect_to select_organization_path, alert: "Please select an organization first."
        return
      end
      @production = Current.organization.productions.find(params.expect(:production_id))
      sync_current_production(@production)
    end

    def set_audition_request
      @audition_request = @audition_cycle.audition_requests.find(params.expect(:id))
    end

    def set_audition_cycle
      if params[:audition_cycle_id].present?
        @audition_cycle = AuditionCycle.find(params[:audition_cycle_id])
      else
        @audition_cycle = @production.active_audition_cycle
        unless @audition_cycle
          redirect_to manage_production_path(@production), alert: "No active audition cycle. Please create one first."
        end
      end
    end

    def ensure_audition_cycle_active
      unless @audition_cycle&.active
        redirect_to manage_production_signups_auditions_cycle_request_path(@production, @audition_cycle, @audition_request),
                    alert: "This audition cycle is archived and cannot be modified."
      end
    end

    def audition_request_params
      params.expect(audition_request: %i[audition_cycle_id person_id video_url])
    end
  end
end
