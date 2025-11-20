class Manage::AuditionsController < Manage::ManageController
  before_action :set_production, except: %i[ add_to_session remove_from_session move_to_session ]
  before_action :check_production_access, except: %i[ add_to_session remove_from_session move_to_session ]
  before_action :set_audition_cycle, except: %i[ index schedule_auditions add_to_session remove_from_session move_to_session ]
  before_action :set_audition, only: %i[ show edit update destroy ]
  before_action :ensure_user_is_manager, except: %i[index show prepare publicize review run casting casting_select schedule_auditions]

  # GET /auditions
  def index
    @active_audition_cycle = @production.active_audition_cycle
    @past_audition_cycles = @production.audition_cycles.where(active: false).order(created_at: :desc)
  end

  # GET /auditions/prepare
  def prepare
    redirect_to_archived_summary if @audition_cycle && !@audition_cycle.active
  end

  # GET /auditions/publicize
  def publicize
    redirect_to_archived_summary if @audition_cycle && !@audition_cycle.active
  end

  # GET /auditions/review
  def review
    redirect_to_archived_summary if @audition_cycle && !@audition_cycle.active

    # Load existing email templates for default groups
    @invitation_accepted_group = @audition_cycle&.email_groups&.find_by(group_id: "invitation_accepted")
    @invitation_not_accepted_group = @audition_cycle&.email_groups&.find_by(group_id: "invitation_not_accepted")
  end

  # GET /auditions/run
  def run
    redirect_to_archived_summary if @audition_cycle && !@audition_cycle.active
  end

  # GET /auditions/casting
  def casting
    redirect_to_archived_summary if @audition_cycle && !@audition_cycle.active

    @talent_pools = @production.talent_pools
    # Get people who actually auditioned (have an Audition record for this audition cycle's sessions)
    audition_session_ids = @audition_cycle.audition_sessions.pluck(:id)
    @auditioned_people = Person.joins(:auditions)
                                .where(auditions: { audition_session_id: audition_session_ids })
                                .distinct
                                .order(:name)
    @cast_assignment_stages = @audition_cycle.cast_assignment_stages.includes(:person, :talent_pool)
  end

  # GET /auditions/casting/select
  def casting_select
    redirect_to_archived_summary if @audition_cycle && !@audition_cycle.active

    @talent_pools = @production.talent_pools
    # Get people who actually auditioned (have an Audition record for this audition cycle's sessions)
    audition_session_ids = @audition_cycle.audition_sessions.pluck(:id)
    @auditioned_people = Person.joins(:auditions)
                                .where(auditions: { audition_session_id: audition_session_ids })
                                .distinct
                                .order(:name)
    @cast_assignment_stages = @audition_cycle.cast_assignment_stages.includes(:person, :talent_pool)
  end

  # PATCH /auditions/finalize_invitations
  def finalize_invitations
    audition_cycle = @production.audition_cycle
    audition_cycle.update(finalize_audition_invitations: params[:finalize])
    redirect_to manage_production_auditions_review_path(@production), notice: "Audition invitations #{params[:finalize] == 'true' ? 'finalized' : 'unfin finalized'}"
  end

  # GET /auditions/schedule_auditions
  def schedule_auditions
    @audition_cycle = AuditionCycle.find(params[:id])
    @audition_sessions = @audition_cycle.audition_sessions.includes(:location).order(start_at: :asc)

    filter = params[:filter]
    audition_requests = @audition_cycle.audition_requests

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
    @scheduled_request_ids = Audition.joins(:audition_session).where(audition_session: { audition_cycle_id: @audition_cycle.id }).pluck(:audition_request_id).uniq
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
      audition_requests: { requestable_type: "Person", requestable_id: audition_request.person.id }
    ).exists?

    unless existing
      Audition.create!(audition_request: audition_request, audition_session: audition_session, person: audition_request.person)
    end

    # Get the production and audition_cycle
    production = audition_session.production
    audition_cycle = audition_request.audition_cycle

    # Get the filter from params
    filter = params[:filter] || "to_be_scheduled"

    # Determine which audition_requests to show
    available_people = audition_cycle.audition_requests

    if filter == "all"
      available_people = available_people.where(status: [ :unreviewed, :undecided, :passed, :accepted ])
    elsif filter == "accepted"
      available_people = available_people.where(status: :accepted)
    else
      # "to_be_scheduled" (default)
      available_people = available_people.where(status: :accepted)
      available_people = available_people.where.not(id: Audition.where(audition_session: audition_cycle.audition_sessions).select(:audition_request_id))
    end

    available_people = available_people.includes(:person).order(created_at: :asc)

    # Get list of already scheduled person IDs for this audition cycle
    audition_sessions = audition_cycle.audition_sessions.includes(:location).order(start_at: :asc)
    scheduled_person_ids = Audition.joins(:audition_request).where(audition_session: audition_sessions).pluck(:person_id).uniq
    scheduled_request_ids = Audition.joins(:audition_session).where(audition_session: { audition_cycle_id: audition_cycle.id }).pluck(:audition_request_id).uniq

    # Re-render the right list and the dropzone
    right_list_html = render_to_string(partial: "manage/auditions/right_list", locals: { available_people: available_people, production: production, audition_cycle: audition_cycle, filter: filter, scheduled_request_ids: scheduled_request_ids, scheduled_person_ids: scheduled_person_ids })
    dropzone_html = render_to_string(partial: "manage/audition_sessions/dropzone", locals: { audition_session: audition_session })

    # Also re-render the sessions list to update all dropzones
    sessions_list_html = render_to_string(partial: "manage/auditions/sessions_list", locals: { audition_sessions: audition_cycle.audition_sessions.includes(:location).order(start_at: :asc) })

    render json: { right_list_html: right_list_html, dropzone_html: dropzone_html, sessions_list_html: sessions_list_html }
  end

  def remove_from_session
    audition = Audition.find(params[:audition_id])
    audition_session = AuditionSession.find(params[:audition_session_id])
    audition_session.auditions.delete(audition)
    audition.destroy!

    # Get the production and audition_cycle
    production = audition_session.production
    audition_cycle = audition.audition_request.audition_cycle

    # Get the filter from params
    filter = params[:filter] || "to_be_scheduled"

    # Determine which audition_requests to show
    available_people = audition_cycle.audition_requests

    if filter == "all"
      available_people = available_people.where(status: [ :unreviewed, :undecided, :passed, :accepted ])
    elsif filter == "accepted"
      available_people = available_people.where(status: :accepted)
    else
      # "to_be_scheduled" (default)
      available_people = available_people.where(status: :accepted)
      available_people = available_people.where.not(id: Audition.where(audition_session: audition_cycle.audition_sessions).select(:audition_request_id))
    end

    available_people = available_people.includes(:person).order(created_at: :asc)

    # Get list of already scheduled person IDs and audition request IDs for this audition cycle
    audition_sessions = audition_cycle.audition_sessions.includes(:location).order(start_at: :asc)
    scheduled_person_ids = Audition.joins(:audition_request).where(audition_session: audition_sessions).pluck(:person_id).uniq
    scheduled_request_ids = Audition.joins(:audition_session).where(audition_session: { audition_cycle_id: audition_cycle.id }).pluck(:audition_request_id).uniq

    right_list_html = render_to_string(partial: "manage/auditions/right_list", locals: { available_people: available_people, production: production, audition_cycle: audition_cycle, filter: filter, scheduled_request_ids: scheduled_request_ids, scheduled_person_ids: scheduled_person_ids })
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
      audition_requests: { requestable_type: "Person", requestable_id: audition.person_id }
    ).where.not(id: audition.id).exists?

    unless existing
      # Update the audition to the new session
      audition.update!(audition_session: new_audition_session)
    end

    # Get the production and audition_cycle
    production = new_audition_session.production
    audition_cycle = audition.audition_request.audition_cycle

    # Get the filter from params
    filter = params[:filter] || "to_be_scheduled"

    # Determine which audition_requests to show
    available_people = audition_cycle.audition_requests

    if filter == "all"
      available_people = available_people.where(status: [ :unreviewed, :undecided, :passed, :accepted ])
    elsif filter == "accepted"
      available_people = available_people.where(status: :accepted)
    else
      # "to_be_scheduled" (default)
      available_people = available_people.where(status: :accepted)
      available_people = available_people.where.not(id: Audition.where(audition_session: audition_cycle.audition_sessions).select(:audition_request_id))
    end

    available_people = available_people.includes(:person).order(created_at: :asc)

    # Get list of already scheduled person IDs and audition request IDs for this audition cycle
    audition_sessions = audition_cycle.audition_sessions.includes(:location).order(start_at: :asc)
    scheduled_person_ids = Audition.joins(:audition_request).where(audition_session: audition_sessions).pluck(:person_id).uniq
    scheduled_request_ids = Audition.joins(:audition_session).where(audition_session: { audition_cycle_id: audition_cycle.id }).pluck(:audition_request_id).uniq

    right_list_html = render_to_string(partial: "manage/auditions/right_list", locals: { available_people: available_people, production: production, audition_cycle: audition_cycle, filter: filter, scheduled_request_ids: scheduled_request_ids, scheduled_person_ids: scheduled_person_ids })

    # Also re-render the sessions list to update all dropzones
    sessions_list_html = render_to_string(partial: "manage/auditions/sessions_list", locals: { audition_sessions: audition_sessions })

    render json: { right_list_html: right_list_html, sessions_list_html: sessions_list_html }
  end

  # POST /auditions/add_to_cast_assignment
  def add_to_cast_assignment
    talent_pool = @production.talent_pools.find(params[:talent_pool_id])
    person = Person.find(params[:person_id])

    CastAssignmentStage.find_or_create_by(
      audition_cycle_id: @audition_cycle.id,
      talent_pool_id: talent_pool.id,
      person_id: person.id
    )

    head :ok
  end

  # POST /auditions/remove_from_cast_assignment
  def remove_from_cast_assignment
    talent_pool = @production.talent_pools.find(params[:talent_pool_id])
    CastAssignmentStage.where(
      audition_cycle_id: @audition_cycle.id,
      talent_pool_id: talent_pool.id,
      person_id: params[:person_id]
    ).destroy_all

    head :ok
  end

  # POST /auditions/finalize_and_notify
  def finalize_and_notify
    audition_cycle = @audition_cycle

    unless audition_cycle
      render json: { error: "No audition cycle found" }, status: :unprocessable_entity
      return
    end

    # Get all cast assignment stages and email assignments
    cast_assignment_stages = audition_cycle.cast_assignment_stages.includes(:cast, :person)
    email_assignments = audition_cycle.audition_email_assignments.includes(:person).index_by(&:person_id)
    email_groups = audition_cycle.email_groups.index_by(&:group_id)

    # Get people who need notifications:
    # 1. People with pending stages (being added now)
    # 2. People who auditioned but have no stages at all AND haven't been notified yet
    pending_stage_person_ids = cast_assignment_stages.where(status: :pending).pluck(:person_id).uniq
    finalized_stage_person_ids = cast_assignment_stages.where(status: :finalized).pluck(:person_id).uniq

    audition_session_ids = audition_cycle.audition_sessions.pluck(:id)
    all_auditioned_people = Person.joins(:auditions)
                               .where(auditions: { audition_session_id: audition_session_ids })
                               .distinct

    # Exclude people who:
    # 1. Are already finalized (have been notified of acceptance), OR
    # 2. Have been notified of rejection for this cycle
    auditioned_people = all_auditioned_people.reject do |p|
      finalized_stage_person_ids.include?(p.id) ||
      (p.casting_notification_sent_at.present? && p.notified_for_audition_cycle_id == audition_cycle.id)
    end

    # Get default email templates from the view (we'll need to pass these or store them)
    talent_pools_by_id = @production.talent_pools.index_by(&:id)

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
        talent_pool = talent_pools_by_id[stage.talent_pool_id]
        email_body = generate_default_cast_email(person, talent_pool, @production)

        # Add person to the actual cast (not just the staging area)
        unless talent_pool.people.include?(person)
          talent_pool.people << person
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

          # Store the sent email in the stage if it exists
          if stage
            stage.update(notification_email: personalized_body, status: :finalized)
          else
            # For people not being added (no stage), track that they've been notified
            person.update(
              casting_notification_sent_at: Time.current,
              notified_for_audition_cycle_id: audition_cycle.id
            )
          end
        rescue => e
          Rails.logger.error "Failed to send email to #{person.email}: #{e.message}"
        end
      end
    end

    # Mark all remaining cast assignment stages as finalized (no longer destroy them)
    cast_assignment_stages.where(status: :pending).update_all(status: :finalized)

    # Mark the audition cycle as having finalized casting
    audition_cycle.update(casting_finalized_at: Time.current)

    redirect_to casting_manage_production_audition_cycle_path(@production, audition_cycle),
                notice: "#{emails_sent} notification email#{emails_sent != 1 ? 's' : ''} sent and #{people_added_to_casts} people added to casts."
  end

  # POST /auditions/finalize_and_notify_invitations
  def finalize_and_notify_invitations
    audition_cycle = @audition_cycle

    unless audition_cycle
      render json: { error: "No audition cycle found" }, status: :unprocessable_entity
      return
    end

    # Get all audition requests
    audition_requests = audition_cycle.audition_requests.includes(:person)

    # Get scheduled person IDs to determine who should get invitation vs rejection
    scheduled_person_ids = audition_cycle.audition_sessions.joins(:auditions).pluck("auditions.person_id").uniq

    # Process requests that:
    # 1. Haven't been notified yet (invitation_notification_sent_at is nil), OR
    # 2. Have been notified but their status has changed since then, OR
    # 3. Have been notified but their scheduling status has changed (e.g., they were added to schedule)
    requests_to_process = audition_requests.select do |req|
      req.invitation_notification_sent_at.nil? ||
      req.notified_status != req.status ||
      (scheduled_person_ids.include?(req.person_id) != req.notified_scheduled)
    end

    email_assignments = audition_cycle.audition_email_assignments.includes(:person).index_by(&:person_id)
    email_groups = audition_cycle.email_groups.where(group_type: "audition").index_by(&:group_id)

    emails_sent = 0

    requests_to_process.each do |request|
      person = request.person
      email_assignment = email_assignments[person.id]

      # Determine which email template to use
      email_body = nil

      if email_assignment&.email_group_id.present?
        # Custom email group
        custom_group = email_groups[email_assignment.email_group_id]
        email_body = custom_group&.email_template
      elsif scheduled_person_ids.include?(person.id)
        # Person is scheduled for an audition - send invitation
        email_body = generate_default_invitation_email(person, @production, audition_cycle)
      else
        # Person is not scheduled - send rejection
        email_body = generate_default_not_invited_email(person, @production)
      end      # Send the email if we have a body
      if email_body.present? && person.email.present?
        # Replace [Name] placeholder with actual name
        personalized_body = email_body.gsub("[Name]", person.name)

        begin
          Manage::AuditionMailer.invitation_notification(person, @production, personalized_body).deliver_later
          emails_sent += 1

          # Mark this request as notified with current status and scheduling status
          is_scheduled = scheduled_person_ids.include?(person.id)
          request.update(
            invitation_notification_sent_at: Time.current,
            notified_status: request.status,
            notified_scheduled: is_scheduled
          )
        rescue => e
          Rails.logger.error "Failed to send email to #{person.email}: #{e.message}"
        end
      end
    end

    # Set finalize_audition_invitations to true so applicants can see results
    audition_cycle.update(finalize_audition_invitations: true)

    redirect_to review_manage_production_audition_cycle_path(@production, audition_cycle),
                notice: "#{emails_sent} invitation email#{emails_sent != 1 ? 's' : ''} sent successfully."
  end

  private

    def generate_default_cast_email(person, talent_pool, production)
      <<~EMAIL
        Dear #{person.name},

        Congratulations! We're excited to invite you to join the #{talent_pool.name} for #{production.name}.

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

    def generate_default_invitation_email(person, production, audition_cycle)
      if audition_cycle.audition_type == "video_upload"
        <<~EMAIL
          Dear #{person.name},

          Congratulations! You've been invited to audition for #{production.name}.

          Your audition materials have been received and are under review. We'll notify you once decisions have been made.

          We look forward to seeing your work!

          Best regards,
          The #{production.name} Team
        EMAIL
      else
        <<~EMAIL
          Dear #{person.name},

          Congratulations! You've been invited to audition for #{production.name}.

          Your audition schedule is now available. Please log in to view your audition time and location details.

          We look forward to seeing you!

          Best regards,
          The #{production.name} Team
        EMAIL
      end
    end

    def generate_default_not_invited_email(person, production)
      <<~EMAIL
        Dear #{person.name},

        Thank you so much for your interest in #{production.name}. We truly appreciate you taking the time to apply.

        Unfortunately, we won't be able to offer you an audition for this production at this time. We received many qualified applicants and had to make some difficult decisions.

        We encourage you to apply for future productions and wish you all the best in your performing arts journey.

        Best regards,
        The #{production.name} Team
      EMAIL
    end

    def set_production
      @production = Current.organization.productions.find(params.expect(:production_id))
    end

    def set_audition_cycle
      if params[:id].present?
        # When coming from /audition_cycles/:id/prepare (or other workflow steps)
        @audition_cycle = @production.audition_cycles.find(params[:id])
      else
        # Default to active audition cycle (for legacy routes or index page)
        @audition_cycle = @production.active_audition_cycle
        unless @audition_cycle
          redirect_to manage_production_path(@production), alert: "No active audition cycle. Please create one first."
        end
      end
    end

    def set_audition
      if params[:audition_session_id].present?
        # Nested route: /audition_cycles/:audition_cycle_id/audition_sessions/:audition_session_id/auditions/:id
        @audition_session = AuditionSession.find(params[:audition_session_id])
        @audition = @audition_session.auditions.find(params.expect(:id))
      else
        # Direct route for audition show (if needed)
        @audition = Audition.joins(:audition_session).where(audition_sessions: { audition_cycle_id: @audition_cycle.id }).find(params.expect(:id))
      end
    end

    # Only allow a list of trusted parameters through.
    def audition_params
      params.expect(audition: [ :audition_session_id, :audition_request_id ])
    end

    def redirect_to_archived_summary
      redirect_to manage_production_audition_cycle_path(@production, @audition_cycle)
    end
end
