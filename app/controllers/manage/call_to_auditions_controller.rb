class Manage::CallToAuditionsController < Manage::ManageController
  before_action :set_production
  before_action :set_call_to_audition, only: %i[ edit update destroy preview ]

  # Use the public facing layout on the preview
  layout "application"

  # GET /call_to_auditions/new
  def new
    @call_to_audition = CallToAudition.new
  end

  # GET /call_to_auditions/1/edit
  def edit
  end

  # POST /call_to_auditions
  def create
    @call_to_audition = CallToAudition.new(call_to_audition_params)
    @call_to_audition.production = @production

    # Create a random hex code for the audition link
    @call_to_audition.hex_code = SecureRandom.alphanumeric(5).upcase

    # Make sure it's unique and regenerate if not
    while CallToAudition.exists?(hex_code: @call_to_audition.hex_code)
      @call_to_audition.hex_code = SecureRandom.alphanumeric(5).upcase
    end

    if @call_to_audition.save
      redirect_to edit_manage_production_call_to_audition_path(@production, @call_to_audition), notice: "Call to Audition was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /call_to_auditions/1
  def update
    if @call_to_audition.update(call_to_audition_params)
      redirect_to manage_production_auditions_path(@production), notice: "Call to Audition was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /call_to_auditions/1
  def destroy
    @call_to_audition.destroy!
    redirect_to [ :manage, @production ], notice: "Call to Audition was successfully deleted.", status: :see_other
  end

  def preview
    @audition_request = AuditionRequest.new
    @person = @audition_request.build_person
    @questions = @call_to_audition.questions.order(:created_at) # TODO Change this to be re-arrangeable
    @answers = {}
  end

  private
   def set_production
      @production = Production.find(params.expect(:production_id))
    end

    def set_call_to_audition
      @call_to_audition = CallToAudition.find(params.expect(:id))
    end

    def call_to_audition_params
      params.expect(call_to_audition: [ :production_id, :opens_at, :closes_at, :header_text, :success_text, :hex_code ])
    end
end
