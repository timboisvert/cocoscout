# frozen_string_literal: true

module Manage
  class AuditionRequestsController < Manage::ManageController
    before_action :set_production
    before_action :check_production_access
    before_action :set_audition_cycle
    before_action :set_audition_request, only: %i[show edit_answers edit_video update destroy set_status]
    before_action :ensure_user_is_manager, except: %i[index show]

    def index
      # Store the status filter
      @filter = params[:filter] || session[:audition_requests_filter] || "all"
      session[:audition_requests_filter] = @filter

      # Process the filter
      @audition_requests = @audition_cycle.audition_requests

      case @filter
      when "unreviewed", "undecided", "accepted", "passed"
        @audition_requests = @audition_requests.where(status: @filter).order(:created_at)
      when "all"
        @audition_requests = @audition_requests.order(:created_at)
      else
        @filter = "all"
        @audition_requests = @audition_requests.order(:created_at)
      end
    end

    def show
      # Since an audition request starts in the "unreviewed" state, if it's being viewed,
      # we can assume it's being reviewed, so move it to "undecided".
      @audition_request.undecided! if @audition_request.unreviewed?

      # Get the requestable (Person or Group)
      @requestable = @audition_request.requestable

      # Get the answers
      @answers = @audition_request.answers.includes(:question)

      # Get status counts for buttons
      @status_counts = @audition_cycle.audition_requests.group(:status).count

      # Load availability data if enabled
      return unless @audition_cycle.include_availability_section

      @shows = @production.shows.where("date_and_time >= ?", Time.current).order(:date_and_time)
      @shows = @shows.where(id: @audition_cycle.availability_show_ids) if @audition_cycle.availability_show_ids.present?

      @availability = {}
      ShowAvailability.where(available_entity: @requestable, show_id: @shows.pluck(:id)).each do |show_availability|
        @availability[show_availability.show_id.to_s] = show_availability.status.to_s
      end
    end

    def new
      @audition_request = @audition_cycle.audition_requests.new
      @audition_request.status = :unreviewed
    end

    def create
      @audition_request = @audition_cycle.audition_requests.new(audition_request_params)
      @audition_request.audition_cycle = @audition_cycle
      @audition_request.status = :unreviewed

      if @audition_request.save
        redirect_to manage_production_audition_cycle_audition_requests_path(@production, @audition_cycle),
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
        redirect_to manage_production_audition_cycle_audition_request_path(@production, @audition_cycle, @audition_request),
                    notice: "Sign-up successfully updated", status: :see_other
      else
        render :edit_answers, status: :unprocessable_entity
      end
    end

    def destroy
      @audition_request.destroy!
      redirect_to manage_production_audition_cycle_audition_requests_path(@production, @audition_cycle),
                  notice: "Sign-up successfully deleted", status: :see_other
    end

    def set_status
      @audition_request.status = params.expect(:status)

      if @audition_request.save
        redirect_back_or_to manage_production_audition_cycle_audition_requests_path(@production, @audition_cycle)
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    def set_production
      @production = Current.organization.productions.find(params.expect(:production_id))
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

    def audition_request_params
      params.expect(audition_request: %i[audition_cycle_id person_id video_url])
    end
  end
end
