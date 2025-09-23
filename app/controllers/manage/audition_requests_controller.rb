class Manage::AuditionRequestsController < Manage::ManageController
  before_action :set_production
  before_action :set_audition_request, only: %i[ show edit update destroy set_status ]
  before_action :set_call_to_audition

  def index
    if params[:status].present?
      @audition_requests = AuditionRequest.where(status: params[:status]).order(:created_at)
    else
      @audition_requests = AuditionRequest.order(:created_at)
    end
  end

  def show
    # Since an audition request starts in the "unreviewed" state, if it's being viewed,
    # we can assume it's being reviewed, so move it to "undecided".
    if @audition_request.unreviewed?
      @audition_request.undecided!
    end

    # Get the person
    @person = @audition_request.person

    # Get the answers
    @answers = @audition_request.answers.includes(:question)
  end

  def new
    @audition_request = AuditionRequest.new
    @audition_request.status = :unreviewed
  end

  def edit
  end

  def create
    @audition_request = AuditionRequest.new(audition_request_params)
    @audition_request.call_to_audition = @call_to_audition
    @audition_request.status = :unreviewed

    if @audition_request.save
      redirect_to manage_production_call_to_audition_audition_requests_path(@production, @call_to_audition), notice: "Audition request was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @audition_request.update(audition_request_params)
      redirect_to manage_production_call_to_audition_audition_requests_path(@production, @call_to_audition), notice: "Audition request was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @audition_request.destroy!
    redirect_to manage_production_call_to_audition_audition_requests_path(@production, @call_to_audition), notice: "Audition request was successfully deleted.", status: :see_other
  end

  def set_status
    @audition_request.status = params.expect(:status)

    if @audition_request.save
      redirect_back_or_to manage_production_call_to_audition_audition_requests_path(@production, @call_to_audition)
    else
      render :show, status: :unprocessable_entity
    end
  end

  private
    def set_production
      @production = Production.find(params.expect(:production_id))
    end

    def set_audition_request
      @audition_request = @production.audition_requests(filter: "all").find(params.expect(:id))
    end

    def set_call_to_audition
      @call_to_audition = CallToAudition.find(params.expect(:call_to_audition_id))
    end

    def audition_request_params
      params.expect(audition_request: [ :call_to_audition_id, :person_id ])
    end
end
