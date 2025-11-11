class Manage::AuditionsController < Manage::ManageController
  before_action :set_production, except: %i[ add_to_session remove_from_session move_to_session ]
  before_action :check_production_access, except: %i[ add_to_session remove_from_session move_to_session ]
  before_action :set_audition, only: %i[ show edit update destroy ]
  before_action :ensure_user_is_manager, except: %i[index show prepare publicize review run casting casting_select]

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
    # Get people who actually auditioned (have an Audition record for this production's sessions)
    audition_session_ids = @production.audition_sessions.pluck(:id)
    @auditioned_people = Person.joins(:auditions)
                                .where(auditions: { audition_session_id: audition_session_ids })
                                .distinct
                                .order(:name)
    @cast_assignment_stages = @production.cast_assignment_stages.includes(:person, :cast)
  end

  # GET /auditions/casting/select
  def casting_select
    @casts = @production.casts
    # Get people who actually auditioned (have an Audition record for this production's sessions)
    audition_session_ids = @production.audition_sessions.pluck(:id)
    @auditioned_people = Person.joins(:auditions)
                                .where(auditions: { audition_session_id: audition_session_ids })
                                .distinct
                                .order(:name)
    @cast_assignment_stages = @production.cast_assignment_stages.includes(:person, :cast)
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

  # POST /auditions/add_to_cast_assignment
  def add_to_cast_assignment
    cast = @production.casts.find(params[:cast_id])
    person = Person.find(params[:person_id])

    CastAssignmentStage.find_or_create_by(
      production_id: @production.id,
      cast_id: cast.id,
      person_id: person.id
    )

    head :ok
  end

  # POST /auditions/remove_from_cast_assignment
  def remove_from_cast_assignment
    cast = @production.casts.find(params[:cast_id])
    CastAssignmentStage.where(
      production_id: @production.id,
      cast_id: cast.id,
      person_id: params[:person_id]
    ).destroy_all

    head :ok
  end

  # POST /auditions/finalize_and_notify
  def finalize_and_notify
    call_to_audition = @production.call_to_audition

    unless call_to_audition
      render json: { error: "No call to audition found" }, status: :unprocessable_entity
      return
    end

    # Get all people who auditioned
    audition_session_ids = @production.audition_sessions.pluck(:id)
    auditioned_people = Person.joins(:auditions)
                               .where(auditions: { audition_session_id: audition_session_ids })
                               .distinct

    # Get all cast assignment stages and email assignments
    cast_assignment_stages = @production.cast_assignment_stages.includes(:cast, :person)
    email_assignments = call_to_audition.audition_email_assignments.includes(:person).index_by(&:person_id)
    email_groups = call_to_audition.email_groups.index_by(&:group_id)

    # Get default email templates from the view (we'll need to pass these or store them)
    casts_by_id = @production.casts.index_by(&:id)

    emails_sent = 0
    people_added_to_casts = 0

    auditioned_people.each do |person|
      # Check if person has a cast assignment stage (they're being added to a cast)
      stage = cast_assignment_stages.find { |s| s.person_id == person.id }
      email_assignment = email_assignments[person.id]

      # Determine which email template to use
      email_body = nil

      if email_assignment&.email_group_id.present?
        # Custom email group
        custom_group = email_groups[email_assignment.email_group_id]
        email_body = custom_group&.email_template
      elsif stage
        # Default "added to cast" email
        cast = casts_by_id[stage.cast_id]
        email_body = generate_default_cast_email(person, cast, @production)

        # Add person to the actual cast (not just the staging area)
        unless cast.people.include?(person)
          cast.people << person
          people_added_to_casts += 1
        end
      else
        # Default "not being added" email
        email_body = generate_default_rejection_email(person, @production)
      end

      # Send the email if we have a body
      if email_body.present? && person.email.present?
        # Replace [Name] placeholder with actual name
        personalized_body = email_body.gsub("[Name]", person.name)

        begin
          Manage::AuditionMailer.casting_notification(person, @production, personalized_body).deliver_later
          emails_sent += 1
        rescue => e
          Rails.logger.error "Failed to send email to #{person.email}: #{e.message}"
        end
      end
    end

    # Mark all cast assignment stages as finalized by deleting them (they're now in the actual casts)
    cast_assignment_stages.destroy_all

    render json: {
      success: true,
      emails_sent: emails_sent,
      people_added_to_casts: people_added_to_casts
    }
  end

  private

    def generate_default_cast_email(person, cast, production)
      <<~EMAIL
        Dear #{person.name},

        Congratulations! We're excited to invite you to join the #{cast.name} for #{production.name}.

        Your audition impressed us, and we believe you'll be a great addition to the team. We look forward to working with you.

        Please confirm your acceptance by replying to this email.

        Best regards,
        The #{production.name} Team
      EMAIL
    end

    def generate_default_rejection_email(person, production)
      <<~EMAIL
        Dear #{person.name},

        Thank you so much for auditioning for #{production.name}. We truly appreciate the time and effort you put into your audition.

        Unfortunately, we won't be able to offer you a role in this production at this time. We were impressed by your talent and encourage you to audition for future productions.

        We hope to work with you in the future.

        Best regards,
        The #{production.name} Team
      EMAIL
    end

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
