# frozen_string_literal: true

module Manage
  class AuditionsController < Manage::ManageController
    before_action :set_production, except: %i[org_index add_to_session remove_from_session move_to_session]
    before_action :check_production_access, except: %i[org_index add_to_session remove_from_session move_to_session]
    before_action :set_audition_cycle,
                  except: %i[org_index index archive schedule_auditions add_to_session remove_from_session move_to_session]
    before_action :set_audition, only: %i[show edit update destroy cast_audition_vote]
    before_action :ensure_user_is_manager,
                  except: %i[org_index index archive show casting casting_select schedule_auditions cast_audition_vote]
    before_action :ensure_audition_cycle_active, only: %i[cast_audition_vote]

    # GET /casting/auditions (org-wide)
    def org_index
      @filter = params[:filter] # 'in_person' or 'video'

      # Get in-house productions the user has access to (exclude third-party)
      @productions = Current.user.accessible_productions.type_in_house.includes(:audition_cycles).order(:name)

      # Get all active audition cycles across all productions
      @all_active_cycles = AuditionCycle.where(production: @productions, active: true)
                                         .includes(:production, :audition_requests, :audition_sessions)
                                         .order(created_at: :desc)

      # Get all archived audition cycles
      @all_archived_cycles = AuditionCycle.where(production: @productions, active: false)
                                           .includes(:production)
                                           .order(created_at: :desc)

      # Apply filter if provided
      if @filter == "in_person"
        @cycles = @all_active_cycles.where(allow_in_person_auditions: true)
        @archived_cycles = @all_archived_cycles.where(allow_in_person_auditions: true)
      elsif @filter == "video"
        @cycles = @all_active_cycles.where(allow_video_submissions: true, allow_in_person_auditions: false)
        @archived_cycles = @all_archived_cycles.where(allow_video_submissions: true, allow_in_person_auditions: false)
      else
        @cycles = @all_active_cycles
        @archived_cycles = @all_archived_cycles
      end
    end

    # GET /auditions (production-level)
    def index
      @active_audition_cycle = @production.active_audition_cycle
      @past_audition_cycles = @production.audition_cycles.where(active: false).order(created_at: :desc).limit(3)

      # Apply filter if provided
      @filter = params[:filter]
      # Filter is used in the view to show filtered audition cycles

      # Check for wizard in progress
      @wizard_in_progress = session[:audition_wizard].present? && session[:audition_wizard][@production.id.to_s].present?
    end

    # GET /auditions/archive
    def archive
      @past_audition_cycles = @production.audition_cycles.where(active: false).order(created_at: :desc)
    end

    # GET /auditions/settings — cycle configuration (replaces /prepare and /edit)
    def settings
      redirect_to_archived_summary if @audition_cycle && !@audition_cycle.active
      @wizard_in_progress = session[:audition_wizard].present? && session[:audition_wizard][@production.id.to_s].present?
      @talent_pool_people = @production.effective_talent_pool&.people&.order(:name) || []
    end

    # PATCH /auditions/update_reviewers
    def update_reviewers
      reviewer_access_type = params[:reviewer_access_type]
      person_ids = params[:person_ids] || []

      @audition_cycle.update!(reviewer_access_type: reviewer_access_type)

      # Update reviewers
      @audition_cycle.audition_reviewers.destroy_all
      if reviewer_access_type == "specific"
        person_ids.each do |person_id|
          @audition_cycle.audition_reviewers.create!(person_id: person_id) if person_id.present?
        end
      end

      redirect_to manage_settings_signups_auditions_cycle_path(@production, @audition_cycle),
                  notice: "Audition review team updated successfully."
    end

    # GET /auditions/casting
    def casting
      redirect_to_archived_summary if @audition_cycle && !@audition_cycle.active

      @talent_pool = @production.effective_talent_pool

      if @audition_cycle.video_only?
        # For video-only auditions, use audition requests instead of auditions
        audition_requests = @audition_cycle.audition_requests.includes(:requestable)
        @auditioned_people = audition_requests.map(&:requestable).compact.sort_by { |r| r.name.to_s }
      else
        # For in-person auditions (or hybrid), use auditions from audition sessions
        audition_session_ids = @audition_cycle.audition_sessions.pluck(:id)
        auditions = Audition.where(audition_session_id: audition_session_ids)
                            .select(:auditionable_type, :auditionable_id)
                            .distinct
        @auditioned_people = auditions.map(&:auditionable).compact.sort_by { |a| a.name.to_s }
      end

      @cast_assignment_stages = @audition_cycle.cast_assignment_stages.includes(:assignable, :talent_pool)
    end

    # GET /auditions/casting/select
    def casting_select
      redirect_to_archived_summary if @audition_cycle && !@audition_cycle.active

      @talent_pool = @production.effective_talent_pool
      @auditionee_vote_counts = {}

      if @audition_cycle.video_only?
        # For video-only auditions, use audition requests instead of auditions
        audition_requests = @audition_cycle.audition_requests
                              .includes(:audition_request_votes, :requestable)

        audition_requests.each do |request|
          next unless request.requestable
          key = [ request.requestable_type, request.requestable_id ]
          @auditionee_vote_counts[key] = request.vote_counts
        end

        @auditioned_people = audition_requests.map(&:requestable).compact.sort_by do |r|
          key = [ r.class.name, r.id ]
          counts = @auditionee_vote_counts[key] || {}
          -(counts[:yes] || 0)
        end
      else
        # For in-person auditions, use auditions from audition sessions
        audition_session_ids = @audition_cycle.audition_sessions.pluck(:id)
        auditions = Audition.where(audition_session_id: audition_session_ids)
                            .includes(:audition_votes, :auditionable)
                            .select(:id, :auditionable_type, :auditionable_id)
                            .distinct

        auditions.each do |audition|
          next unless audition.auditionable
          key = [ audition.auditionable_type, audition.auditionable_id ]
          @auditionee_vote_counts[key] = audition.vote_counts
        end

        @auditioned_people = auditions.map(&:auditionable).compact.sort_by do |a|
          key = [ a.class.name, a.id ]
          counts = @auditionee_vote_counts[key] || {}
          -(counts[:yes] || 0)
        end
      end

      @cast_assignment_stages = @audition_cycle.cast_assignment_stages.includes(:assignable, :talent_pool)
      @current_talent_pool_members = @talent_pool.talent_pool_memberships.includes(:member).map(&:member).compact.sort_by { |m| m.name.to_s }
    end

    # PATCH /auditions/finalize_invitations
    def finalize_invitations
      audition_cycle = @production.audition_cycle
      audition_cycle.update(finalize_audition_invitations: params[:finalize])
      redirect_to manage_signups_auditions_cycle_requests_path(@production, audition_cycle),
                  notice: "Audition invitations #{params[:finalize] == 'true' ? 'finalized' : 'unfinalized'}"
    end

    # GET /auditions/schedule_auditions
    def schedule_auditions
      @audition_cycle = AuditionCycle.find(params[:id])
      @audition_sessions = @audition_cycle.audition_sessions
        .includes(:location, auditions: :auditionable)
        .order(start_at: :asc)

      # Show all sign-ups ordered by yes vote count descending
      @available_people = @audition_cycle.audition_requests
        .includes(:requestable, :audition_request_votes)
        .left_joins(:audition_request_votes)
        .select("audition_requests.*, COUNT(CASE WHEN audition_request_votes.vote = 0 THEN 1 END) AS yes_count")
        .group("audition_requests.id")
        .order("yes_count DESC, audition_requests.created_at ASC")

      @scheduled_auditionables = Audition.joins(:audition_request).where(audition_session: @audition_sessions).pluck(
        :auditionable_type, :auditionable_id
      ).to_set
      @scheduled_request_ids = Audition.joins(:audition_session).where(audition_session: { audition_cycle_id: @audition_cycle.id }).pluck(:audition_request_id).uniq

      # Per-session availability the assign modal uses to group/order auditionees.
      # AuditionSessionAvailability is keyed by the auditionable (the request's
      # requestable), so map it back to the request id for the modal payload.
      request_by_entity = @available_people.index_by { |r| "#{r.requestable_type}_#{r.requestable_id}" }
      @session_availability = Hash.new { |h, k| h[k] = {} }
      AuditionSessionAvailability
        .where(audition_session_id: @audition_sessions.map(&:id))
        .find_each do |a|
          req = request_by_entity["#{a.available_entity_type}_#{a.available_entity_id}"]
          next unless req
          @session_availability[a.audition_session_id.to_s][req.id.to_s] = a.status
        end

      # Which audition_requests are already in each session (to mark "Added").
      @in_session_request_ids = @audition_sessions.each_with_object({}) do |s, h|
        h[s.id.to_s] = s.auditions.map(&:audition_request_id).compact.map(&:to_s)
      end

      # Default messages for the Review & Notify modal (manager can edit them).
      # "[Name]" is replaced per-recipient when sending.
      @invited_default_message = default_message_html(
        "audition_invitation",
        "<div>Hi [Name],</div><div><br></div><div>Great news — you've been scheduled for an audition for #{ERB::Util.html_escape(@production.name)}. We look forward to seeing you!</div>"
      )
      @not_invited_default_message = default_message_html(
        "audition_not_invited",
        "<div>Hi [Name],</div><div><br></div><div>Thank you so much for your interest in #{ERB::Util.html_escape(@production.name)}. After careful consideration, we won't be moving forward with an audition at this time. We truly appreciate you and hope to see you audition with us again.</div>"
      )
    end

    # GET /auditions/:id/notify_preview — who's getting an audition vs not,
    # for the Review & Notify modal on the schedule page (computed fresh, since
    # scheduling changes client-side after page load).
    def notify_preview
      @audition_cycle = AuditionCycle.find(params[:id])
      sessions = @audition_cycle.audition_sessions.includes(auditions: :auditionable).order(:start_at)

      session_labels = Hash.new { |h, k| h[k] = [] }
      sessions.each do |s|
        label = s.start_at.strftime("%a, %b %-d at %-l:%M %p")
        s.auditions.each { |a| session_labels["#{a.auditionable_type}_#{a.auditionable_id}"] << label }
      end
      scheduled_keys = session_labels.keys.to_set

      invited = []
      not_invited = []
      @audition_cycle.audition_requests.includes(:requestable).each do |req|
        ent = req.requestable
        next unless ent
        variant = ent.respond_to?(:safe_headshot_variant) ? ent.safe_headshot_variant(:thumb) : nil
        entry = {
          name: ent.name,
          initials: (ent.respond_to?(:initials) ? ent.initials : ent.name.to_s[0, 2].upcase),
          headshot: (variant ? helpers.url_for(variant) : nil),
          notified: req.invitation_notification_sent_at.present?
        }
        if scheduled_keys.include?("#{req.requestable_type}_#{req.requestable_id}")
          entry[:sessions] = session_labels["#{req.requestable_type}_#{req.requestable_id}"].uniq
          invited << entry
        else
          not_invited << entry
        end
      end

      render json: {
        invited: invited.sort_by { |e| e[:name].to_s },
        not_invited: not_invited.sort_by { |e| e[:name].to_s },
        invited_count: invited.size,
        not_invited_count: not_invited.size,
        already_notified_count: (invited + not_invited).count { |e| e[:notified] }
      }
    end

    # GET /auditions/1
    def show
      @auditionable = @audition.auditionable
      @audition_request = @audition.audition_request

      # Eager load profile data
      if @auditionable.present?
        @profile_headshots = @auditionable.profile_headshots
        @profile_resumes = @auditionable.profile_resumes
        @socials = @auditionable.respond_to?(:socials) ? @auditionable.socials : []
      end

      # Get answers from the audition request
      @answers = @audition_request&.answers&.includes(:question) || []

      # Get all votes for this audition
      @votes = @audition.audition_votes.includes(user: :default_person)

      # Load availability data if enabled
      if @audition_cycle.include_availability_section && @auditionable.present?
        @shows = @production.shows.where("date_and_time >= ?", Time.current).order(:date_and_time)
        @shows = @shows.where(id: @audition_cycle.availability_show_ids) if @audition_cycle.availability_show_ids.present?

        @show_availabilities = {}
        ShowAvailability.where(available_entity: @auditionable, show_id: @shows.pluck(:id)).each do |sa|
          @show_availabilities[sa.show_id] = sa
        end
      end

      # Load audition session availability
      if @audition_cycle.include_audition_availability_section
        @audition_sessions_list = @audition_cycle.audition_sessions.where("start_at >= ?", Time.current).order(:start_at)

        @audition_availability = {}
        AuditionSessionAvailability.where(available_entity: @auditionable, audition_session_id: @audition_sessions_list.pluck(:id)).each do |sa|
          @audition_availability[sa.audition_session_id.to_s] = sa.status.to_s
        end
      end

      # Navigation between auditions in session
      @auditions_in_session = @audition.audition_session.auditions.order(:id)
      current_index = @auditions_in_session.find_index(@audition)
      @prev_audition = current_index && current_index > 0 ? @auditions_in_session[current_index - 1] : nil
      @next_audition = current_index && current_index < @auditions_in_session.size - 1 ? @auditions_in_session[current_index + 1] : nil
    end

    # POST /auditions/:id/cast_audition_vote
    def cast_audition_vote
      vote = @audition.audition_votes.find_or_initialize_by(user: Current.user)
      vote.vote = params[:vote] if params[:vote].present?
      vote.comment = params[:comment] if params.key?(:comment)

      if vote.save
        respond_to do |format|
          redirect_url = manage_signups_auditions_cycle_session_audition_path(@production, @audition_cycle, @audition.audition_session, @audition)
          redirect_url += "?tab=#{params[:tab]}" if params[:tab].present?
          format.html { redirect_back_or_to redirect_url, notice: "Vote recorded" }
          format.json do
            votes = AuditionVote.where(audition_id: @audition.id)
                                .includes(user: :default_person)
                                .order(created_at: :desc)
                                .to_a
            counts = {
              yes: votes.count { |v| v.vote == "yes" },
              no: votes.count { |v| v.vote == "no" },
              maybe: votes.count { |v| v.vote == "maybe" }
            }
            votes_html = render_to_string(partial: "manage/audition_requests/votes_list",
                                          locals: { votes: votes },
                                          formats: [ :html ])
            render json: {
              success: true,
              vote: vote.vote,
              comment: vote.comment,
              counts: counts,
              votes_html: votes_html
            }
          end
        end
      else
        respond_to do |format|
          redirect_url = manage_signups_auditions_cycle_session_audition_path(@production, @audition_cycle, @audition.audition_session, @audition)
          redirect_url += "?tab=#{params[:tab]}" if params[:tab].present?
          format.html { redirect_back_or_to redirect_url, alert: vote.errors.full_messages.join(", ") }
          format.json { render json: { success: false, errors: vote.errors.full_messages }, status: :unprocessable_entity }
        end
      end
    end

    # GET /auditions/new
    def new
      @audition = Audition.new
    end

    # GET /auditions/1/edit
    def edit; end

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

      # Check if this requestable is already in this session
      existing = Audition.joins(:audition_request).where(
        audition_session: audition_session,
        audition_requests: { requestable_type: audition_request.requestable_type,
                             requestable_id: audition_request.requestable_id }
      ).exists?

      unless existing
        Audition.create!(audition_request: audition_request, audition_session: audition_session,
                         auditionable: audition_request.requestable)
      end

      # Get the production and audition_cycle
      production = audition_session.production
      audition_cycle = audition_request.audition_cycle

      # New click-to-add UI only needs this session's slots — skip the heavy
      # legacy drag partials (right_list / sessions_list / dropzone).
      if params[:ui] == "v2"
        render json: {
          session_id: audition_session.id,
          session_slots_html: session_slots_html_for(audition_session, audition_cycle),
          scheduled_request_ids: scheduled_request_ids_for(audition_cycle)
        } and return
      end

      # Show all sign-ups ordered by yes vote count descending
      available_people = audition_cycle.audition_requests
        .includes(:requestable, :audition_request_votes)
        .left_joins(:audition_request_votes)
        .select("audition_requests.*, COUNT(CASE WHEN audition_request_votes.vote = 0 THEN 1 END) AS yes_count")
        .group("audition_requests.id")
        .order("yes_count DESC, audition_requests.created_at ASC")

      # Get list of already scheduled auditionables for this audition cycle
      audition_sessions = audition_cycle.audition_sessions.includes(:location).order(start_at: :asc)
      scheduled_auditionables = Audition.joins(:audition_request).where(audition_session: audition_sessions).pluck(
        :auditionable_type, :auditionable_id
      )
      scheduled_request_ids = Audition.joins(:audition_session).where(audition_session: { audition_cycle_id: audition_cycle.id }).pluck(:audition_request_id).uniq

      # Re-render the right list and the dropzone
      right_list_html = render_to_string(partial: "manage/auditions/right_list",
                                         locals: { available_people: available_people, production: production, audition_cycle: audition_cycle,
                                                   scheduled_request_ids: scheduled_request_ids, scheduled_auditionables: scheduled_auditionables })
      dropzone_html = render_to_string(partial: "manage/audition_sessions/dropzone",
                                       locals: { audition_session: audition_session })

      # Also re-render the sessions list to update all dropzones
      sessions_list_html = render_to_string(partial: "manage/auditions/sessions_list",
                                            locals: {
                                              audition_sessions: audition_cycle.audition_sessions.includes(:location).order(start_at: :asc),
                                              production: production,
                                              audition_cycle: audition_cycle
                                            })

      render json: { right_list_html: right_list_html, dropzone_html: dropzone_html,
                     sessions_list_html: sessions_list_html,
                     session_id: audition_session.id,
                     session_slots_html: session_slots_html_for(audition_session, audition_cycle),
                     scheduled_request_ids: scheduled_request_ids }
    end

    def remove_from_session
      audition = Audition.find(params[:audition_id])
      audition_session = AuditionSession.find(params[:audition_session_id])
      audition_session.auditions.delete(audition)
      audition.destroy!

      # Get the production and audition_cycle
      production = audition_session.production
      audition_cycle = audition.audition_request.audition_cycle

      if params[:ui] == "v2"
        render json: {
          session_id: audition_session.id,
          session_slots_html: session_slots_html_for(audition_session, audition_cycle),
          scheduled_request_ids: scheduled_request_ids_for(audition_cycle)
        } and return
      end

      # Show all sign-ups ordered by yes vote count descending
      available_people = audition_cycle.audition_requests
        .includes(:requestable, :audition_request_votes)
        .left_joins(:audition_request_votes)
        .select("audition_requests.*, COUNT(CASE WHEN audition_request_votes.vote = 0 THEN 1 END) AS yes_count")
        .group("audition_requests.id")
        .order("yes_count DESC, audition_requests.created_at ASC")

      # Get list of already scheduled auditionables and audition request IDs for this audition cycle
      audition_sessions = audition_cycle.audition_sessions.includes(:location).order(start_at: :asc)
      scheduled_auditionables = Audition.joins(:audition_request).where(audition_session: audition_sessions).pluck(
        :auditionable_type, :auditionable_id
      )
      scheduled_request_ids = Audition.joins(:audition_session).where(audition_session: { audition_cycle_id: audition_cycle.id }).pluck(:audition_request_id).uniq

      right_list_html = render_to_string(partial: "manage/auditions/right_list",
                                         locals: { available_people: available_people, production: production, audition_cycle: audition_cycle,
                                                   scheduled_request_ids: scheduled_request_ids, scheduled_auditionables: scheduled_auditionables })
      dropzone_html = render_to_string(partial: "manage/audition_sessions/dropzone",
                                       locals: { audition_session: audition_session })

      # Also re-render the sessions list to update all dropzones
      sessions_list_html = render_to_string(partial: "manage/auditions/sessions_list",
                                            locals: {
                                              audition_sessions: audition_sessions,
                                              production: production,
                                              audition_cycle: audition_cycle
                                            })

      render json: { right_list_html: right_list_html, dropzone_html: dropzone_html,
                     sessions_list_html: sessions_list_html,
                     session_id: audition_session.id,
                     session_slots_html: session_slots_html_for(audition_session, audition_cycle),
                     scheduled_request_ids: scheduled_request_ids }
    end

    def move_to_session
      audition = Audition.find(params[:audition_id])
      new_audition_session = AuditionSession.find(params[:audition_session_id])

      # Check if auditionable (person/group) is already in the new session
      existing = Audition.where(
        audition_session: new_audition_session,
        auditionable_type: audition.auditionable_type,
        auditionable_id: audition.auditionable_id
      ).where.not(id: audition.id).exists?

      unless existing
        # Update the audition to the new session
        audition.update!(audition_session: new_audition_session)
      end

      # Get the production and audition_cycle
      production = new_audition_session.production
      audition_cycle = audition.audition_request.audition_cycle

      # Show all sign-ups ordered by yes vote count descending
      available_people = audition_cycle.audition_requests
        .includes(:requestable, :audition_request_votes)
        .left_joins(:audition_request_votes)
        .select("audition_requests.*, COUNT(CASE WHEN audition_request_votes.vote = 0 THEN 1 END) AS yes_count")
        .group("audition_requests.id")
        .order("yes_count DESC, audition_requests.created_at ASC")

      # Get list of already scheduled auditionables and audition request IDs for this audition cycle
      audition_sessions = audition_cycle.audition_sessions.includes(:location).order(start_at: :asc)
      scheduled_auditionables = Audition.joins(:audition_request).where(audition_session: audition_sessions).pluck(
        :auditionable_type, :auditionable_id
      )
      scheduled_request_ids = Audition.joins(:audition_session).where(audition_session: { audition_cycle_id: audition_cycle.id }).pluck(:audition_request_id).uniq

      right_list_html = render_to_string(partial: "manage/auditions/right_list",
                                         locals: { available_people: available_people, production: production, audition_cycle: audition_cycle,
                                                   scheduled_request_ids: scheduled_request_ids, scheduled_auditionables: scheduled_auditionables })

      # Also re-render the sessions list to update all dropzones
      sessions_list_html = render_to_string(partial: "manage/auditions/sessions_list",
                                            locals: {
                                              audition_sessions: audition_sessions,
                                              production: production,
                                              audition_cycle: audition_cycle
                                            })

      render json: { right_list_html: right_list_html, sessions_list_html: sessions_list_html }
    end

    # POST /auditions/add_to_cast_assignment
    def add_to_cast_assignment
      talent_pool = @production.effective_talent_pool
      auditionee_type = params[:auditionee_type]
      auditionee_id = params[:auditionee_id]
      decision_type = params[:decision_type] || "cast"

      # Remove any existing stage for this auditionee (in case they're being moved between buckets)
      CastAssignmentStage.where(
        audition_cycle_id: @audition_cycle.id,
        assignable_type: auditionee_type,
        assignable_id: auditionee_id
      ).destroy_all

      CastAssignmentStage.create!(
        audition_cycle_id: @audition_cycle.id,
        talent_pool_id: talent_pool.id,
        assignable_type: auditionee_type,
        assignable_id: auditionee_id,
        decision_type: decision_type
      )

      head :ok
    end

    # POST /auditions/remove_from_cast_assignment
    def remove_from_cast_assignment
      talent_pool = @production.effective_talent_pool
      CastAssignmentStage.where(
        audition_cycle_id: @audition_cycle.id,
        talent_pool_id: talent_pool.id,
        assignable_type: params[:auditionee_type] || "Person",
        assignable_id: params[:auditionee_id] || params[:person_id]
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

      # Get all cast assignment stages
      cast_assignment_stages = audition_cycle.cast_assignment_stages.includes(:talent_pool, :assignable)

      # Get the effective talent pool for this production (may be shared)
      talent_pool = @production.effective_talent_pool
      talent_pools_by_id = talent_pool ? { talent_pool.id => talent_pool } : {}

      # Get pending stages for recipient count
      pending_stages = cast_assignment_stages.where(status: :pending).includes(:assignable)

      # Count total recipients for batch creation (only people with pending stages)
      total_recipients = pending_stages.sum do |stage|
        assignable = stage.assignable
        next 0 unless assignable
        if assignable.is_a?(Group)
          assignable.group_memberships.select(&:notifications_enabled?).count { |m| m.person.email.present? }
        else
          assignable.email.present? ? 1 : 0
        end
      end

      # Create email batch if sending to multiple recipients
      email_batch = nil
      if total_recipients > 1
        email_batch = EmailBatch.create!(
          user: Current.user,
          subject: ContentTemplateService.render_subject("audition_added_to_cast", { production_name: @production.name }),
          recipient_count: total_recipients,
          sent_at: Time.current
        )
      end

      emails_sent = 0
      messages_sent = 0
      auditionees_added_to_casts = 0

      # Build notification batches for AuditionNotificationService
      cast_notifications = []
      rejection_notifications = []

      # Get pending stages grouped by decision type
      pending_cast_stages = cast_assignment_stages.where(status: :pending, decision_type: :cast)
      pending_rejection_stages = cast_assignment_stages.where(status: :pending, decision_type: :rejected)

      # Process cast assignments (people being added to talent pool)
      pending_cast_stages.each do |stage|
        assignable = stage.assignable
        next unless assignable

        talent_pool = talent_pools_by_id[stage.talent_pool_id]
        email_result = generate_default_cast_email(assignable, talent_pool, @production)
        email_subject = email_result[:subject]
        email_body = email_result[:body]

        # Add assignable to the actual talent pool (not just the staging area)
        membership_exists = TalentPoolMembership.exists?(
          talent_pool_id: talent_pool.id,
          member_type: assignable.class.name,
          member_id: assignable.id
        )
        unless membership_exists
          TalentPoolMembership.create!(
            talent_pool_id: talent_pool.id,
            member_type: assignable.class.name,
            member_id: assignable.id
          )
          auditionees_added_to_casts += 1
        end

        # Get recipients - for Person it's just them, for Group it's all members with notifications enabled
        recipients = assignable.is_a?(Group) ? assignable.group_memberships.select(&:notifications_enabled?).map(&:person) : [ assignable ]

        recipients.each do |person|
          next unless email_body.present? && person.email.present?

          personalized_body = email_body.gsub("[Name]", person.name)
          cast_notifications << {
            person: person,
            talent_pool: talent_pool,
            body: personalized_body,
            subject: email_subject
          }
        end

        stage.update(notification_email: email_body, status: :finalized)
      end

      # Process rejections (people explicitly marked for rejection)
      pending_rejection_stages.each do |stage|
        assignable = stage.assignable
        next unless assignable

        email_result = generate_default_rejection_email(assignable, @production)
        email_subject = email_result[:subject]
        email_body = email_result[:body]

        # Get recipients - for Person it's just them, for Group it's all members with notifications enabled
        recipients = assignable.is_a?(Group) ? assignable.group_memberships.select(&:notifications_enabled?).map(&:person) : [ assignable ]

        recipients.each do |person|
          next unless email_body.present? && person.email.present?

          personalized_body = email_body.gsub("[Name]", person.name)
          rejection_notifications << {
            person: person,
            body: personalized_body,
            subject: email_subject
          }
        end

        # Track notification for person
        if assignable.is_a?(Person)
          assignable.update(
            casting_notification_sent_at: Time.current,
            notified_for_audition_cycle_id: audition_cycle.id
          )
        end

        stage.update(notification_email: email_body, status: :finalized)
      end

      # Send notifications via service
      notification_results = AuditionNotificationService.send_casting_results(
        production: @production,
        audition_cycle: audition_cycle,
        sender: Current.user,
        cast_assignments: cast_notifications,
        rejections: rejection_notifications,
        email_batch: email_batch
      )
      messages_sent = notification_results[:messages_sent]
      emails_sent = notification_results[:emails_sent]

      # Mark all remaining cast assignment stages as finalized (no longer destroy them)
      cast_assignment_stages.where(status: :pending).update_all(status: :finalized)

      # Mark the audition cycle as having finalized casting and disable audition voting
      audition_cycle.update(casting_finalized_at: Time.current, audition_voting_enabled: false)

      notice_parts = []
      notice_parts << "#{messages_sent} message#{'s' unless messages_sent == 1}" if messages_sent > 0
      notice_parts << "#{emails_sent} email#{'s' unless emails_sent == 1}" if emails_sent > 0
      notice_parts << "#{auditionees_added_to_casts} auditionee#{'s' unless auditionees_added_to_casts == 1} added to casts"

      redirect_to manage_casting_signups_auditions_cycle_path(@production, audition_cycle),
                  notice: notice_parts.join(" and ") + "."
    end

    # POST /auditions/finalize_and_notify_invitations
    def finalize_and_notify_invitations
      audition_cycle = @audition_cycle

      unless audition_cycle
        render json: { error: "No audition cycle found" }, status: :unprocessable_entity
        return
      end

      # Get all audition requests
      audition_requests = audition_cycle.audition_requests.includes(:requestable)

      # Get scheduled auditionables to determine who should get invitation vs rejection
      scheduled_auditionables = audition_cycle.audition_sessions.joins(:auditions)
                                              .pluck("auditions.auditionable_type", "auditions.auditionable_id")
                                              .map { |type, id| [ type, id ] }
                                              .to_set

      # Manager-edited messages from the Review & Notify modal (plain text).
      # When present, they override the templates. [Name] is personalized per
      # recipient, and invited people get their session time(s) appended.
      invited_body_custom = params[:invited_body].presence
      not_invited_body_custom = params[:not_invited_body].presence
      session_details = audition_cycle.audition_sessions.includes(:auditions).order(:start_at)
        .each_with_object(Hash.new { |h, k| h[k] = [] }) do |s, acc|
          label = s.start_at.strftime("%A, %b %-d at %-l:%M %p")
          s.auditions.each { |a| acc[[ a.auditionable_type, a.auditionable_id ]] << label }
        end

      # Process requests that:
      # 1. Haven't been notified yet (invitation_notification_sent_at is nil), OR
      # 2. Have been notified but their scheduling status has changed (e.g., they were added to schedule)
      requests_to_process = audition_requests.select do |req|
        req.invitation_notification_sent_at.nil? ||
          (scheduled_auditionables.include?([ req.requestable_type, req.requestable_id ]) != req.notified_scheduled)
      end

      email_assignments = audition_cycle.audition_email_assignments.includes(:assignable)
                                        .index_by { |a| [ a.assignable_type, a.assignable_id ] }
      email_groups = audition_cycle.email_groups.where(group_type: "audition").index_by(&:group_id)

      # Count total recipients for batch creation
      total_recipients = requests_to_process.sum do |req|
        requestable = req.requestable
        next 0 unless requestable
        if requestable.is_a?(Group)
          requestable.group_memberships.includes(:person).select(&:notifications_enabled?).count { |m| m.person.email.present? && (m.person.user.nil? || m.person.user.notification_enabled?(:audition_invitations)) }
        else
          (requestable.email.present? && (requestable.user.nil? || requestable.user.notification_enabled?(:audition_invitations))) ? 1 : 0
        end
      end

      # Create email batch if sending to multiple recipients
      email_batch = nil
      if total_recipients > 1
        email_batch = EmailBatch.create!(
          user: Current.user,
          subject: ContentTemplateService.render_subject("audition_invitation", { production_name: @production.name }),
          recipient_count: total_recipients,
          sent_at: Time.current
        )
      end

      # Build notification batches for AuditionNotificationService
      invitation_notifications = []
      not_invited_notifications = []
      # Track which requests to mark as notified (only after successful send)
      requests_to_mark = []

      requests_to_process.each do |request|
        requestable = request.requestable
        next unless requestable # Skip if requestable was deleted


        # Determine which email template to use
        email_body = nil
        is_scheduled = scheduled_auditionables.include?([ requestable.class.name, requestable.id ])

        if is_scheduled
          # Invited: use the manager's edited message if provided, else let the
          # service render the template (which injects audition details).
          email_body = invited_body_custom
        else
          # Not invited: manager's edited message, else the default template.
          email_body = not_invited_body_custom.presence || generate_default_not_invited_email(requestable, @production)
        end

        # Get recipients (single person for Person, multiple members for Group)
        recipients = if requestable.is_a?(Person)
                       [ requestable ]
        elsif requestable.is_a?(Group)
                       # Get all group members who have notifications enabled
                       requestable.group_memberships.includes(:person).select(&:notifications_enabled?).map(&:person)
        else
                       []
        end

        # Collect notifications for each recipient
        recipients.each do |recipient|
          next unless recipient.email.present?
          # Check if user has audition invitation notifications enabled
          next if recipient.user.present? && !recipient.user.notification_enabled?(:audition_invitations)

          # Replace [Name] placeholder with actual name.
          personalized_body = email_body&.gsub("[Name]", recipient.name)

          if is_scheduled
            # The manager's message is rich-text HTML. Append this person's
            # session time(s) as HTML; otherwise let the service render the
            # template (body: nil).
            body =
              if personalized_body.present?
                details = session_details[[ requestable.class.name, requestable.id ]].uniq
                if details.any?
                  items = details.map { |d| "<li>#{ERB::Util.html_escape(d)}</li>" }.join
                  personalized_body + "<p><strong>Your audition time#{details.size == 1 ? "" : "s"}:</strong></p><ul>#{items}</ul>"
                else
                  personalized_body
                end
              end
            invitation_notifications << { person: recipient, body: body }
          else
            next unless personalized_body.present?
            not_invited_notifications << { person: recipient, body: personalized_body }
          end
        end

        # Track this request to mark as notified after successful send
        requests_to_mark << { request: request, is_scheduled: is_scheduled }
      end

      # Send notifications via service
      notification_results = AuditionNotificationService.send_audition_invitations(
        production: @production,
        audition_cycle: audition_cycle,
        sender: Current.user,
        invitations: invitation_notifications,
        not_invited: not_invited_notifications,
        email_batch: email_batch
      )

      # Only mark requests as notified AFTER successful send
      requests_to_mark.each do |item|
        item[:request].update(
          invitation_notification_sent_at: Time.current,
          notified_scheduled: item[:is_scheduled]
        )
      end

      messages_sent = notification_results[:messages_sent]
      emails_sent = notification_results[:emails_sent]

      # Set finalize_audition_invitations to true so applicants can see results
      # Also disable both voting types since scheduling is finalized
      audition_cycle.update(finalize_audition_invitations: true, voting_enabled: false, audition_voting_enabled: false)

      notice_parts = []
      notice_parts << "#{messages_sent} message#{'s' unless messages_sent == 1}" if messages_sent > 0
      notice_parts << "#{emails_sent} email#{'s' unless emails_sent == 1}" if emails_sent > 0
      notice_parts << "sent successfully" if notice_parts.any?
      notice_text = notice_parts.any? ? notice_parts.join(" and ") : "No notifications sent"

      redirect_to manage_signups_auditions_cycle_requests_path(@production, audition_cycle),
                  notice: notice_text
    end

    private

    # Re-renders one session's assigned-auditionee slots after an add/remove,
    # for the click-to-add scheduling UI (audition-assign controller swaps it in).
    def session_slots_html_for(session, audition_cycle)
      session.auditions.reload
      render_to_string(
        partial: "manage/auditions/session_slots",
        formats: [ :html ],
        locals: { session: session, production: session.production, audition_cycle: audition_cycle }
      )
    end

    # HTML default for an editable rich-text notify message; falls back
    # gracefully if the content template isn't present.
    def default_message_html(key, fallback_html)
      return fallback_html unless ContentTemplateService.exists?(key)
      ContentTemplateService.render_body(key, { recipient_name: "[Name]", production_name: @production.name }).presence || fallback_html
    rescue StandardError
      fallback_html
    end

    def scheduled_request_ids_for(audition_cycle)
      Audition.joins(:audition_session)
              .where(audition_session: { audition_cycle_id: audition_cycle.id })
              .distinct.pluck(:audition_request_id)
    end

    def ensure_audition_cycle_active
      unless @audition_cycle.active
        redirect_to manage_signups_auditions_cycle_session_audition_path(@production, @audition_cycle, @audition.audition_session, @audition),
                    alert: "This audition cycle is archived. Voting is not allowed."
      end
    end

    def generate_default_cast_email(person, _talent_pool, production)
      ContentTemplateService.render("audition_added_to_cast", {
        recipient_name: person.name,
        production_name: production.name,
        confirm_by_date: "[date]"
      })
    end

    def generate_default_rejection_email(person, production)
      ContentTemplateService.render("audition_not_cast", {
        recipient_name: person.name,
        production_name: production.name
      })
    end

    def generate_default_invitation_email(person, production, _audition_cycle)
      ContentTemplateService.render_body("audition_invitation", {
        recipient_name: person.name,
        production_name: production.name
      })
    end

    def generate_default_not_invited_email(person, production)
      ContentTemplateService.render_body("audition_not_invited", {
        recipient_name: person.name,
        production_name: production.name
      })
    end

    def set_production
      unless Current.organization
        redirect_to select_organization_path, alert: "Please select an organization first."
        return
      end
      @production = Current.organization.productions.find(params.expect(:production_id))
      sync_current_production(@production)
    end

    def set_audition_cycle
      # Check for cycle_id in new routes, or audition_cycle_id/id in legacy routes
      cycle_id = params[:cycle_id] || params[:audition_cycle_id] || params[:id]

      if cycle_id.present?
        # When coming from /audition_cycles/:id or /audition_cycles/:audition_cycle_id/*
        @audition_cycle = @production.audition_cycles.find_by(id: cycle_id)
        unless @audition_cycle
          redirect_to manage_signups_auditions_path(@production), alert: "Audition cycle not found."
          nil
        end
      else
        # Default to active audition cycle (for legacy routes or index page)
        @audition_cycle = @production.active_audition_cycle
        unless @audition_cycle
          redirect_to manage_production_path(@production), alert: "No active audition cycle. Please create one first."
        end
      end
    end

    def set_audition
      session_id = params[:session_id] || params[:audition_session_id]
      if session_id.present?
        # Nested route: /signups/auditions/:production_id/:cycle_id/sessions/:session_id/auditions/:id
        @audition_session = AuditionSession.find(session_id)
        @audition = @audition_session.auditions.find(params.expect(:id))
      else
        # Direct route for audition show (if needed)
        @audition = Audition.joins(:audition_session).where(audition_sessions: { audition_cycle_id: @audition_cycle.id }).find(params.expect(:id))
      end
    end

    # Only allow a list of trusted parameters through.
    def audition_params
      params.expect(audition: %i[audition_session_id audition_request_id])
    end

    def redirect_to_archived_summary
      redirect_to manage_signups_auditions_cycle_path(@production, @audition_cycle)
    end
  end
end
