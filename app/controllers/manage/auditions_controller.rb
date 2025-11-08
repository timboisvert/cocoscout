class Manage::AuditionsController < Manage::ManageController
  before_action :set_production, except: %i[ add_to_session remove_from_session ]
  before_action :check_production_access, except: %i[ add_to_session remove_from_session ]
  before_action :set_audition, only: %i[ show edit update destroy ]
  before_action :ensure_user_is_manager, except: %i[index show prepare publicize review run communicate]

  # GET /auditions
  def index
    @auditions = Audition.all
  end

  # GET /auditions/prepare
  def prepare
  end

  # GET /auditions/publicize
  def publicize
  end

  # GET /auditions/review
  def review
  end

  # GET /auditions/run
  def run
  end

  # GET /auditions/communicate
  def communicate
  end

  # GET /auditions/1
  def show
  end

  # GET /auditions/new
  def new
    @audition = Audition.new
  end

  # GET /auditions/1/edit
  def edit
  end

  # POST /auditions
  def create
    @audition = Audition.new(audition_params)

    if @audition.save
      redirect_to @audition, notice: "Audition was successfully created"
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /auditions/1
  def update
    if @audition.update(audition_params)
      redirect_to @audition, notice: "Audition was successfully updated", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /auditions/1
  def destroy
    @audition.destroy!
    redirect_to auditions_path, notice: "Audition was successfully deleted", status: :see_other
  end



  # POST /auditions/add_to_session
  def add_to_session
    audition_request = AuditionRequest.find(params[:audition_request_id])
    audition_session = AuditionSession.find(params[:audition_session_id])

    Audition.create!(audition_request: audition_request, audition_session: audition_session, person: audition_request.person)

    # Re-render the left list and the dropzone partials
    left_list_html = render_to_string(partial: "manage/audition_sessions/left_list", locals: { production: audition_session.production, filter: cookies[:audition_request_filter] })
    dropzone_html = render_to_string(partial: "manage/audition_sessions/dropzone", locals: { audition_session: audition_session })

    render json: { left_list_html: left_list_html, dropzone_html: dropzone_html }
  end

  def remove_from_session
    audition = Audition.find(params[:audition_id])
    audition_session = AuditionSession.find(params[:audition_session_id])
    audition_session.auditions.delete(audition)
    audition.destroy!

    left_list_html = render_to_string(partial: "manage/audition_sessions/left_list", locals: { production: audition_session.production, filter: cookies[:audition_request_filter] })
    dropzone_html = render_to_string(partial: "manage/audition_sessions/dropzone", locals: { audition_session: audition_session })

    render json: { left_list_html: left_list_html, dropzone_html: dropzone_html }
  end


  private
    def set_production
      @production = Current.production_company.productions.find(params.expect(:production_id))
    end

    def set_audition
      @audition = @production.auditions.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def audition_params
      params.expect(audition: [ :audition_session_id, :audition_request_id ])
    end
end
