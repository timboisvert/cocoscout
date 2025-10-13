class Manage::AuditionRequestsController < Manage::ManageController
  before_action :set_production
  before_action :set_audition_request, only: %i[ show edit_answers edit_video update destroy set_status ]
  before_action :set_call_to_audition
  before_action :ensure_user_is_manager, except: %i[ index show ]

  def index
    # Store the status filter
    @filter = (params[:filter] || session[:audition_requests_filter] || "all")
    session[:audition_requests_filter] = @filter

    # Process the filter
    @audition_requests = @production.audition_requests

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
    if @audition_request.unreviewed?
      @audition_request.undecided!
    end

    # Get the person
    @person = @audition_request.person

    # Get the answers
    @answers = @audition_request.answers.includes(:question)

    # Get status counts for buttons
    @status_counts = @call_to_audition.audition_requests.group(:status).count
  end

  def new
    @audition_request = @production.audition_requests.new
    @audition_request.status = :unreviewed
  end

  def create
    @audition_request = @production.audition_requests.new(audition_request_params)
    @audition_request.call_to_audition = @call_to_audition
    @audition_request.status = :unreviewed

    if @audition_request.save
      redirect_to manage_production_call_to_audition_audition_requests_path(@production, @call_to_audition), notice: "Sign-up was successfully created"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit_answers
    @questions = @audition_request.call_to_audition.questions.order(:position) if @call_to_audition.present?

    @answers = {}
    @questions.each do |question|
      answer = @audition_request.answers.find_by(question: question)
      @answers["#{question.id}"] = answer.value if answer
    end
  end

  def edit_video
  end

  def update
    @answers = {}
    if params[:question]
      params[:question].each do |id, keyValue|
        answer = @audition_request.answers.find_or_initialize_by(question: Question.find(id))
        answer.value = keyValue
        answer.save!
        @answers["#{id}"] = answer.value
      end
    end

    if params[:audition_request]
      @audition_request.assign_attributes(audition_request_params)
    end

    if @audition_request.valid?
      @audition_request.save!
      redirect_to manage_production_call_to_audition_audition_request_path(@production, @call_to_audition, @audition_request), notice: "Sign-up successfully updated", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @audition_request.destroy!
    redirect_to manage_production_call_to_audition_audition_requests_path(@production, @call_to_audition), notice: "Sign-up successfully deleted", status: :see_other
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
      @production = Current.production_company.productions.find(params.expect(:production_id))
    end

    def set_audition_request
      @audition_request = @production.audition_requests.find(params.expect(:id))
    end

    def set_call_to_audition
      @call_to_audition = @production.call_to_auditions.find(params.expect(:call_to_audition_id))
    end

    def audition_request_params
      params.expect(audition_request: [ :call_to_audition_id, :person_id, :video_url ])
    end
end
