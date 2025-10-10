class Manage::QuestionsController < Manage::ManageController
  before_action :set_question, only: %i[ edit update destroy ]
  before_action :set_production
  before_action :set_call_to_audition

  # GET /questions
  def index
    @question = @call_to_audition.questions.new
    @question.question_options.build if [ "multiple-multiple", "multiple-single" ].include?(@question.question_type)
    @questions = @call_to_audition.questions.order(:position)
  end

  # GET /questions/1/edit
  def edit
  end

  # POST /questions
  def create
    @question = Question.new(question_params)
    @question.questionable = @call_to_audition
    @questions = @call_to_audition.questions.order(:position)

    if @question.save
      redirect_to manage_production_call_to_audition_questions_path(@production, @call_to_audition), notice: "Question was successfully created."
    else
      @question_error = true
      render :index, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /questions/1
  def update
    if @question.update(question_params)
      redirect_to manage_production_call_to_audition_questions_path(@production, @call_to_audition), notice: "Question was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /questions/1
  def destroy
    @question.destroy!
    redirect_to manage_production_call_to_audition_questions_path(@production, @call_to_audition), notice: "Question was successfully deleted.", status: :see_other
  end

  # POST /questions/reorder
  def reorder
    ids = params[:ids]
    questions = @call_to_audition.questions.where(id: ids)
    ActiveRecord::Base.transaction do
      ids.each_with_index do |id, idx|
        questions.find { |q| q.id == id.to_i }&.update(position: idx + 1)
      end
    end
    head :ok
  end

  private
    def set_question
      @question = Question.find(params[:id]) if params[:id]
    end

    def set_production
      @production = Current.production_company.productions.find(params[:production_id])
    end

    def set_call_to_audition
      @call_to_audition = CallToAudition.find(params[:call_to_audition_id])
    end

    def question_params
      params.require(:question).permit(:key, :text, :question_type, :questionable_id, :questionable_type, question_options_attributes: [ :id, :text, :_destroy ])
    end
end
