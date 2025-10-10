class Manage::AuditionSessionsController < Manage::ManageController
  before_action :set_production
  before_action :set_audition_session_and_audition_and_audition_request, only: %i[ show edit update destroy ]

   def index
    @audition_sessions = @production.audition_sessions

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

    if params[:duplicate].present?
      original = AuditionSession.find_by(id: params[:duplicate], production: @production)
      if original.present?
        @audition_session.start_at = original.start_at
        @audition_session.maximum_auditionees = original.maximum_auditionees
      end
    end
  end

  def edit
  end

  def create
    @audition_session = AuditionSession.new(audition_session_params)
    @audition_session.production = @production

    if @audition_session.save
      redirect_to manage_production_audition_sessions_path(@production), notice: "Audition session was successfully scheduled."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @audition_session.update(audition_session_params)
      redirect_to manage_production_audition_sessions_path(@production), notice: "Audition session was successfully rescheduled.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @audition_session.destroy!
    redirect_to manage_production_audition_sessions_path(@production), notice: "Audition session was successfully canceled.", status: :see_other
  end

  def summary
    @audition_sessions = @production.audition_sessions
  end

  private
    def set_production
      @production = Current.production_company.productions.find(params.expect(:production_id))
    end

    def set_audition_session_and_audition_and_audition_request
      if params[:audition_session_id].present?
        @audition_session = @production.audition_sessions.find(params.expect(:audition_session_id))
        @audition = @audition_session.auditions.find(params.expect(:id))
        @audition_request = @audition.audition_request
      else
        @audition_session = @production.audition_sessions.find(params.expect(:id))
      end
    end

    def audition_session_params
      params.expect(audition_session: [ :production_id, :start_at, :end_at, :maximum_auditionees, :location_id ])
    end
end
