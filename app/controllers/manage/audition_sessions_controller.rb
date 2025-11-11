class Manage::AuditionSessionsController < Manage::ManageController
  before_action :set_call_to_audition
  before_action :set_production
  before_action :check_production_access
  before_action :set_audition_session_and_audition_and_audition_request, only: %i[ show edit update destroy ]
  before_action :ensure_user_is_manager, except: %i[show summary]

  def index
    @audition_sessions = @call_to_audition.audition_sessions.includes(:location).order(start_at: :asc)

    if params[:filter].present?
      cookies[:audition_request_filter] = params[:filter]
    else
      cookies[:audition_request_filter] ||= "to_be_scheduled"
    end
  end

  def show
    if @audition.present?
      @person = @audition_request.person
      @answers = @audition_request.answers.includes(:question)
    end
  end

  def new
    @audition_session = AuditionSession.new

    # Set default location if available
    default_location = Current.production_company.locations.find_by(default: true)
    @audition_session.location_id = default_location.id if default_location

    if params[:duplicate].present?
      original = AuditionSession.find_by(id: params[:duplicate], production: @production)
      if original.present?
        @audition_session.start_at = original.start_at
        @audition_session.maximum_auditionees = original.maximum_auditionees
      end
    end

    render :new, layout: request.xhr? ? false : true
  end

  def edit
    render :edit, layout: request.xhr? ? false : true
  end

  def create
    @audition_session = AuditionSession.new(audition_session_params)
    @audition_session.production = @production
    @audition_session.call_to_audition = @call_to_audition

    if @audition_session.save
      redirect_to manage_production_call_to_audition_audition_sessions_path(@production, @call_to_audition), notice: "Audition session was successfully created", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @audition_session.update(audition_session_params)
      redirect_to manage_production_call_to_audition_audition_sessions_path(@production, @call_to_audition), notice: "Audition session was successfully rescheduled", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @audition_session.destroy!
    redirect_to manage_production_call_to_audition_audition_sessions_path(@production, @call_to_audition), notice: "Audition session was successfully canceled", status: :see_other
  end

  def summary
    @audition_sessions = @call_to_audition.audition_sessions
  end

  private
    def set_call_to_audition
      if params[:call_to_audition_id].present?
        @call_to_audition = CallToAudition.find(params[:call_to_audition_id])
      elsif params[:production_id].present?
        production = Current.production_company.productions.find(params[:production_id])
        @call_to_audition = production.active_call_to_audition
        unless @call_to_audition
          redirect_to manage_production_path(production), alert: "No active call to audition. Please create one first."
        end
      else
        redirect_to manage_path, alert: "Call to audition not found"
      end
    end

    def set_production
      @production = @call_to_audition.production
    end

    def set_audition_session_and_audition_and_audition_request
      if params[:audition_session_id].present?
        @audition_session = @call_to_audition.audition_sessions.find(params.expect(:audition_session_id))
        @audition = @audition_session.auditions.find(params.expect(:id))
        @audition_request = @audition.audition_request
      else
        @audition_session = @call_to_audition.audition_sessions.find(params.expect(:id))
      end
    end

    def audition_session_params
      params.expect(audition_session: [ :start_at, :end_at, :maximum_auditionees, :location_id ])
    end
end
