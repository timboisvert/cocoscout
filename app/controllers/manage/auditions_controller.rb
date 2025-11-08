class Manage::AuditionsController < Manage::ManageController
  before_action :set_production, except: %i[ add_to_session remove_from_session move_to_session ]
  before_action :check_production_access, except: %i[ add_to_session remove_from_session move_to_session ]
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

  # GET /auditions/casting
  def casting
    @casts = @production.casts
    @accepted_audition_requests = @production.call_to_audition&.audition_requests&.where(status: :accepted) || []
  end

  # PATCH /auditions/finalize_invitations
  def finalize_invitations
    call_to_audition = @production.call_to_audition
    call_to_audition.update(finalize_audition_invitations: params[:finalize])
    redirect_to manage_production_auditions_review_path(@production), notice: "Audition invitations #{params[:finalize] == 'true' ? 'finalized' : 'unfin finalized'}"
  end

  # GET /auditions/schedule_auditions
  def schedule_auditions
    @call_to_audition = CallToAudition.find(params[:id])
    @audition_sessions = @production.audition_sessions.includes(:location).order(start_at: :asc)

    filter = params[:filter]
    audition_requests = @call_to_audition.audition_requests

    if filter == "all"
      audition_requests = audition_requests.where(status: [ :unreviewed, :undecided, :passed, :accepted ])
    elsif filter == "accepted"
      audition_requests = audition_requests.where(status: :accepted)
    else
      # "to_be_scheduled" (default)
      audition_requests = audition_requests.where(status: :accepted)
      audition_requests = audition_requests.where.not(id: Audition.where(audition_session: @audition_sessions).select(:audition_request_id))
    end

    @available_people = audition_requests.includes(:person).order(created_at: :asc)
    @scheduled_person_ids = Audition.joins(:audition_request).where(audition_session: @audition_sessions).pluck(:person_id).uniq.to_set
    @scheduled_request_ids = Audition.joins(:audition_session).where(audition_session: { production_id: @production.id }).pluck(:audition_request_id).uniq
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

    # Check if this person is already in this session
    existing = Audition.joins(:audition_request).where(
      audition_session: audition_session,
      audition_requests: { person_id: audition_request.person_id }
    ).exists?

    unless existing
      Audition.create!(audition_request: audition_request, audition_session: audition_session, person: audition_request.person)
    end

    # Get the production and call_to_audition
    production = audition_session.production
    call_to_audition = audition_request.call_to_audition

    # Get the filter from params
    filter = params[:filter] || "to_be_scheduled"

    # Determine which audition_requests to show
    available_people = call_to_audition.audition_requests

    if filter == "all"
      available_people = available_people.where(status: [ :unreviewed, :undecided, :passed, :accepted ])
    elsif filter == "accepted"
      available_people = available_people.where(status: :accepted)
    else
      # "to_be_scheduled" (default)
      available_people = available_people.where(status: :accepted)
      available_people = available_people.where.not(id: Audition.where(audition_session: production.audition_sessions).select(:audition_request_id))
    end

    available_people = available_people.includes(:person).order(created_at: :asc)

    # Get list of already scheduled person IDs for this production
    audition_sessions = production.audition_sessions.includes(:location).order(start_at: :asc)
    scheduled_person_ids = Audition.joins(:audition_request).where(audition_session: audition_sessions).pluck(:person_id).uniq
    scheduled_request_ids = Audition.joins(:audition_session).where(audition_session: { production_id: production.id }).pluck(:audition_request_id).uniq

    # Re-render the right list and the dropzone
    right_list_html = render_to_string(partial: "manage/auditions/right_list", locals: { available_people: available_people, production: production, call_to_audition: call_to_audition, filter: filter, scheduled_request_ids: scheduled_request_ids, scheduled_person_ids: scheduled_person_ids })
    dropzone_html = render_to_string(partial: "manage/audition_sessions/dropzone", locals: { audition_session: audition_session })

    # Also re-render the sessions list to update all dropzones
    sessions_list_html = render_to_string(partial: "manage/auditions/sessions_list", locals: { audition_sessions: production.audition_sessions.includes(:location).order(start_at: :asc) })

    render json: { right_list_html: right_list_html, dropzone_html: dropzone_html, sessions_list_html: sessions_list_html }
  end

  def remove_from_session
    audition = Audition.find(params[:audition_id])
    audition_session = AuditionSession.find(params[:audition_session_id])
    audition_session.auditions.delete(audition)
    audition.destroy!

    # Get the production and call_to_audition
    production = audition_session.production
    call_to_audition = audition.audition_request.call_to_audition

    # Get the filter from params
    filter = params[:filter] || "to_be_scheduled"

    # Determine which audition_requests to show
    available_people = call_to_audition.audition_requests

    if filter == "all"
      available_people = available_people.where(status: [ :unreviewed, :undecided, :passed, :accepted ])
    elsif filter == "accepted"
      available_people = available_people.where(status: :accepted)
    else
      # "to_be_scheduled" (default)
      available_people = available_people.where(status: :accepted)
      available_people = available_people.where.not(id: Audition.where(audition_session: production.audition_sessions).select(:audition_request_id))
    end

    available_people = available_people.includes(:person).order(created_at: :asc)

    # Get list of already scheduled person IDs and audition request IDs for this production
    audition_sessions = production.audition_sessions.includes(:location).order(start_at: :asc)
    scheduled_person_ids = Audition.joins(:audition_request).where(audition_session: audition_sessions).pluck(:person_id).uniq
    scheduled_request_ids = Audition.joins(:audition_session).where(audition_session: { production_id: production.id }).pluck(:audition_request_id).uniq

    right_list_html = render_to_string(partial: "manage/auditions/right_list", locals: { available_people: available_people, production: production, call_to_audition: call_to_audition, filter: filter, scheduled_request_ids: scheduled_request_ids, scheduled_person_ids: scheduled_person_ids })
    dropzone_html = render_to_string(partial: "manage/audition_sessions/dropzone", locals: { audition_session: audition_session })

    # Also re-render the sessions list to update all dropzones
    sessions_list_html = render_to_string(partial: "manage/auditions/sessions_list", locals: { audition_sessions: audition_sessions })

    render json: { right_list_html: right_list_html, dropzone_html: dropzone_html, sessions_list_html: sessions_list_html }
  end

  def move_to_session
    audition = Audition.find(params[:audition_id])
    new_audition_session = AuditionSession.find(params[:audition_session_id])

    # Check if person is already in the new session
    existing = Audition.joins(:audition_request).where(
      audition_session: new_audition_session,
      audition_requests: { person_id: audition.person_id }
    ).where.not(id: audition.id).exists?

    unless existing
      # Update the audition to the new session
      audition.update!(audition_session: new_audition_session)
    end

    # Get the production and call_to_audition
    production = new_audition_session.production
    call_to_audition = audition.audition_request.call_to_audition

    # Get the filter from params
    filter = params[:filter] || "to_be_scheduled"

    # Determine which audition_requests to show
    available_people = call_to_audition.audition_requests

    if filter == "all"
      available_people = available_people.where(status: [ :unreviewed, :undecided, :passed, :accepted ])
    elsif filter == "accepted"
      available_people = available_people.where(status: :accepted)
    else
      # "to_be_scheduled" (default)
      available_people = available_people.where(status: :accepted)
      available_people = available_people.where.not(id: Audition.where(audition_session: production.audition_sessions).select(:audition_request_id))
    end

    available_people = available_people.includes(:person).order(created_at: :asc)

    # Get list of already scheduled person IDs and audition request IDs for this production
    audition_sessions = production.audition_sessions.includes(:location).order(start_at: :asc)
    scheduled_person_ids = Audition.joins(:audition_request).where(audition_session: audition_sessions).pluck(:person_id).uniq
    scheduled_request_ids = Audition.joins(:audition_session).where(audition_session: { production_id: production.id }).pluck(:audition_request_id).uniq

    right_list_html = render_to_string(partial: "manage/auditions/right_list", locals: { available_people: available_people, production: production, call_to_audition: call_to_audition, filter: filter, scheduled_request_ids: scheduled_request_ids, scheduled_person_ids: scheduled_person_ids })

    # Also re-render the sessions list to update all dropzones
    sessions_list_html = render_to_string(partial: "manage/auditions/sessions_list", locals: { audition_sessions: audition_sessions })

    render json: { right_list_html: right_list_html, sessions_list_html: sessions_list_html }
  end

  private
    def set_production
      @production = Current.production_company.productions.find(params.expect(:production_id))
    end

    def set_audition
      if params[:audition_session_id].present?
        # Nested route: /call_to_auditions/:call_to_audition_id/audition_sessions/:audition_session_id/auditions/:id
        @audition_session = AuditionSession.find(params[:audition_session_id])
        @audition = @audition_session.auditions.find(params.expect(:id))
      else
        # Direct route for audition show (if needed)
        @audition = Audition.joins(:audition_session).where(audition_sessions: { production_id: @production.id }).find(params.expect(:id))
      end
    end

    # Only allow a list of trusted parameters through.
    def audition_params
      params.expect(audition: [ :audition_session_id, :audition_request_id ])
    end
end
