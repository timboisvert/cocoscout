class AuditionsController < ApplicationController
  before_action :set_audition, only: %i[ show edit update destroy ]

  # GET /auditions
  def index
    @auditions = Audition.all
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
      redirect_to @audition, notice: "Audition was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /auditions/1
  def update
    if @audition.update(audition_params)
      redirect_to @audition, notice: "Audition was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /auditions/1
  def destroy
    @audition.destroy!
    redirect_to auditions_path, notice: "Audition was successfully destroyed.", status: :see_other
  end



  # POST /auditions/add_to_session
  def add_to_session
    audition_request = AuditionRequest.find(params[:audition_request_id])
    audition_session = AuditionSession.find(params[:audition_session_id])

    audition = Audition.create!(audition_request: audition_request, person: audition_request.person)
    audition_session.auditions << audition unless audition_session.auditions.include?(audition)

    # Re-render the left list and the dropzone partials
    left_list_html = render_to_string(partial: "audition_sessions/left_list", locals: { production: audition_session.production, filter: cookies[:audition_request_filter] })
    dropzone_html = render_to_string(partial: "audition_sessions/dropzone", locals: { audition_session: audition_session })

    render json: { left_list_html: left_list_html, dropzone_html: dropzone_html }
  end

  def remove_from_session
    audition = Audition.find(params[:audition_id])
    audition_session = AuditionSession.find(params[:audition_session_id])
    audition_session.auditions.delete(audition)

    left_list_html = render_to_string(partial: "audition_sessions/left_list", locals: { production: audition_session.production, filter: cookies[:audition_request_filter] })
    dropzone_html = render_to_string(partial: "audition_sessions/dropzone", locals: { audition_session: audition_session })

    render json: { left_list_html: left_list_html, dropzone_html: dropzone_html }
  end


  private
    # Use callbacks to share common setup or constraints between actions.
    def set_audition
      @audition = Audition.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def audition_params
      params.expect(audition: [ :audition_session_id, :audition_request_id ])
    end
end
