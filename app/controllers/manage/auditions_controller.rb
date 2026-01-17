# frozen_string_literal: true

module Manage
  class AuditionsController < Manage::ManageController
    before_action :set_production, except: %i[add_to_session remove_from_session move_to_session]
    before_action :check_production_access, except: %i[add_to_session remove_from_session move_to_session]
    before_action :set_audition_cycle,
                  except: %i[index archive schedule_auditions add_to_session remove_from_session move_to_session]
    before_action :set_audition, only: %i[show edit update destroy cast_audition_vote]
    before_action :ensure_user_is_manager,
                  except: %i[index archive show prepare publicize review run casting casting_select schedule_auditions cast_audition_vote]
    before_action :ensure_user_has_role, only: %i[prepare publicize]
    before_action :ensure_audition_cycle_active, only: %i[cast_audition_vote]

    # GET /auditions
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

    # GET /auditions/prepare
    def prepare
      redirect_to_archived_summary if @audition_cycle && !@audition_cycle.active
      @talent_pool_people = @production.effective_talent_pool.people.order(:name)

      # Check for wizard in progress
      @wizard_in_progress = session[:audition_wizard].present? && session[:audition_wizard][@production.id.to_s].present?
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

      redirect_to prepare_manage_production_signups_auditions_cycle_path(@production, @audition_cycle),
                  notice: "Audition review team updated successfully."
    end

    # GET /auditions/publicize - redirects to prepare (publicize section removed)
    def publicize
      redirect_to prepare_manage_production_signups_auditions_cycle_path(@production, @audition_cycle)
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
      redirect_to review_manage_production_signups_auditions_cycle_path(@production, audition_cycle),
                  notice: "Audition invitations #{params[:finalize] == 'true' ? 'finalized' : 'unfin finalized'}"
    end

    # GET /auditions/schedule_auditions
    def schedule_auditions
      @audition_cycle = AuditionCycle.find(params[:id])
      @audition_sessions = @audition_cycle.audition_sessions.includes(:location).order(start_at: :asc)

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
    end

    # GET /auditions/1
    def show; end

    # POST /auditions/:id/cast_audition_vote
    def cast_audition_vote
      vote = @audition.audition_votes.find_or_initialize_by(user: Current.user)
      vote.vote = params[:vote] if params[:vote].present?
      vote.comment = params[:comment] if params.key?(:comment)

      if vote.save
        respond_to do |format|
          redirect_url = manage_production_signups_auditions_cycle_session_audition_path(@production, @audition_cycle, @audition.audition_session, @audition)
          redirect_url += "?tab=#{params[:tab]}" if params[:tab].present?
          format.html { redirect_back_or_to redirect_url, notice: "Vote recorded" }
          format.json { render json: { success: true, vote: vote.vote, comment: vote.comment } }
        end
      else
        respond_to do |format|
          redirect_url = manage_production_signups_auditions_cycle_session_audition_path(@production, @audition_cycle, @audition.audition_session, @audition)
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
                                            locals: { audition_sessions: audition_cycle.audition_sessions.includes(:location).order(start_at: :asc) })

      render json: { right_list_html: right_list_html, dropzone_html: dropzone_html,
                     sessions_list_html: sessions_list_html }
    end

    def remove_from_session
      audition = Audition.find(params[:audition_id])
      audition_session = AuditionSession.find(params[:audition_session_id])
      audition_session.auditions.delete(audition)
      audition.destroy!

      # Get the production and audition_cycle
      production = audition_session.production
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
      dropzone_html = render_to_string(partial: "manage/audition_sessions/dropzone",
                                       locals: { audition_session: audition_session })

      # Also re-render the sessions list to update all dropzones
      sessions_list_html = render_to_string(partial: "manage/auditions/sessions_list",
                                            locals: { audition_sessions: audition_sessions })

      render json: { right_list_html: right_list_html, dropzone_html: dropzone_html,
                     sessions_list_html: sessions_list_html }
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
                                            locals: { audition_sessions: audition_sessions })

      render json: { right_list_html: right_list_html, sessions_list_html: sessions_list_html }
    end

    # POST /auditions/add_to_cast_assignment
    def add_to_cast_assignment
      talent_pool = @production.effective_talent_pool
      auditionee_type = params[:auditionee_type]
      auditionee_id = params[:auditionee_id]

      CastAssignmentStage.find_or_create_by(
        audition_cycle_id: @audition_cycle.id,
        talent_pool_id: talent_pool.id,
        assignable_type: auditionee_type,
        assignable_id: auditionee_id
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
      cast_assignment_stages = audition_cycle.cast_assignment_stages.includes(:talent_pool)

      # Get auditionees who need notifications:
      # 1. Auditionees with pending stages (being added now)
      # 2. Auditionees who auditioned but have no stages at all AND haven't been notified yet
      cast_assignment_stages.where(status: :pending).pluck(:assignable_type, :assignable_id).uniq
      finalized_stage_tuples = cast_assignment_stages.where(status: :finalized).pluck(:assignable_type,
                                                                                      :assignable_id).uniq

      # Get auditioned assignables - for video-only cycles, use audition requests
      # For in-person or hybrid cycles, use auditions from audition sessions
      if audition_cycle.video_only?
        audition_requests = audition_cycle.audition_requests.includes(:requestable)
        audition_tuples = audition_requests.map { |r| [ r.requestable_type, r.requestable_id ] }.uniq
      else
        audition_session_ids = audition_cycle.audition_sessions.pluck(:id)
        audition_tuples = Audition.where(audition_session_id: audition_session_ids)
                                  .select(:auditionable_type, :auditionable_id)
                                  .distinct
                                  .pluck(:auditionable_type, :auditionable_id)
      end

      # Load all auditioned assignables efficiently
      person_ids = audition_tuples.select { |type, _| type == "Person" }.map(&:last)
      group_ids = audition_tuples.select { |type, _| type == "Group" }.map(&:last)

      people = Person.where(id: person_ids).index_by(&:id)
      groups = Group.where(id: group_ids).includes(:group_memberships).index_by(&:id)

      all_auditioned_assignables = audition_tuples.map do |type, id|
        type == "Person" ? people[id] : groups[id]
      end.compact

      # Exclude auditionees who:
      # 1. Are already finalized (have been notified of acceptance), OR
      # 2. Have been notified of rejection for this cycle (only applies to Person)
      auditioned_assignables = all_auditioned_assignables.reject do |assignable|
        finalized_stage_tuples.include?([ assignable.class.name, assignable.id ]) ||
          (assignable.is_a?(Person) && assignable.casting_notification_sent_at.present? && assignable.notified_for_audition_cycle_id == audition_cycle.id)
      end

      # Get the effective talent pool for this production (may be shared)
      talent_pool = @production.effective_talent_pool
      talent_pools_by_id = talent_pool ? { talent_pool.id => talent_pool } : {}

      # Count total recipients for batch creation
      total_recipients = auditioned_assignables.sum do |assignable|
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
          subject: "Audition Results for #{@production.name}",
          recipient_count: total_recipients,
          sent_at: Time.current
        )
      end

      emails_sent = 0
      auditionees_added_to_casts = 0

      auditioned_assignables.each do |assignable|
        # Check if assignable has a cast assignment stage (they're being added to a cast)
        stage = cast_assignment_stages.find do |s|
          s.assignable_type == assignable.class.name && s.assignable_id == assignable.id
        end

        # Determine which email template to use
        email_subject = nil
        email_body = nil
        if stage
          # Default "added to cast" email
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
        else
          # Default "not being added" email
          email_result = generate_default_rejection_email(assignable, @production)
          email_subject = email_result[:subject]
          email_body = email_result[:body]
        end

        # Get recipients - for Person it's just them, for Group it's all members with notifications enabled
        recipients = assignable.is_a?(Group) ? assignable.group_memberships.select(&:notifications_enabled?).map(&:person) : [ assignable ]

        # Send the email to each recipient
        recipients.each do |person|
          next unless email_body.present? && person.email.present?

          # Replace [Name] placeholder with actual name
          personalized_body = email_body.gsub("[Name]", person.name)

          begin
            Manage::AuditionMailer.casting_notification(person, @production, personalized_body, subject: email_subject, email_batch_id: email_batch&.id).deliver_later
            emails_sent += 1
          rescue StandardError => e
            Rails.logger.error "Failed to send email to #{person.email}: #{e.message}"
          end
        end

        # Update stage or person notification tracking
        if stage
          stage.update(notification_email: email_body, status: :finalized)
        elsif assignable.is_a?(Person)
          # For people not being added (no stage), track that they've been notified
          assignable.update(
            casting_notification_sent_at: Time.current,
            notified_for_audition_cycle_id: audition_cycle.id
          )
        end
      end

      # Mark all remaining cast assignment stages as finalized (no longer destroy them)
      cast_assignment_stages.where(status: :pending).update_all(status: :finalized)

      # Mark the audition cycle as having finalized casting and disable audition voting
      audition_cycle.update(casting_finalized_at: Time.current, audition_voting_enabled: false)

      redirect_to casting_manage_production_signups_auditions_cycle_path(@production, audition_cycle),
                  notice: "#{emails_sent} notification email#{emails_sent != 1 ? 's' : ''} sent and #{auditionees_added_to_casts} auditionee#{auditionees_added_to_casts != 1 ? 's' : ''} added to casts."
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
          subject: "#{@production.name} Auditions",
          recipient_count: total_recipients,
          sent_at: Time.current
        )
      end

      emails_sent = 0

      requests_to_process.each do |request|
        requestable = request.requestable
        next unless requestable # Skip if requestable was deleted


        # Determine which email template to use
        email_body = nil
        is_scheduled = scheduled_auditionables.include?([ requestable.class.name, requestable.id ])

        if is_scheduled
          # Requestable is scheduled for an audition - send invitation
          email_body = generate_default_invitation_email(requestable, @production, audition_cycle)
        else
          # Requestable is not scheduled - send rejection
          email_body = generate_default_not_invited_email(requestable, @production)
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

        # Send the email to each recipient
        recipients.each do |recipient|
          next unless email_body.present? && recipient.email.present?
          # Check if user has audition invitation notifications enabled
          next if recipient.user.present? && !recipient.user.notification_enabled?(:audition_invitations)

          # Replace [Name] placeholder with actual name
          personalized_body = email_body.gsub("[Name]", recipient.name)

          begin
            Manage::AuditionMailer.invitation_notification(recipient, @production, personalized_body, email_batch_id: email_batch&.id).deliver_later
            emails_sent += 1
          rescue StandardError => e
            Rails.logger.error "Failed to send email to #{recipient.email}: #{e.message}"
          end
        end

        # Mark this request as notified with scheduling status
        request.update(
          invitation_notification_sent_at: Time.current,
          notified_scheduled: is_scheduled
        )
      end

      # Set finalize_audition_invitations to true so applicants can see results
      # Also disable both voting types since scheduling is finalized
      audition_cycle.update(finalize_audition_invitations: true, voting_enabled: false, audition_voting_enabled: false)

      redirect_to review_manage_production_signups_auditions_cycle_path(@production, audition_cycle),
                  notice: "#{emails_sent} invitation email#{emails_sent != 1 ? 's' : ''} sent successfully."
    end

    private

    def ensure_audition_cycle_active
      unless @audition_cycle.active
        redirect_to manage_production_signups_auditions_cycle_session_audition_path(@production, @audition_cycle, @audition.audition_session, @audition),
                    alert: "This audition cycle is archived. Voting is not allowed."
      end
    end

    def generate_default_cast_email(person, _talent_pool, production)
      EmailTemplateService.render("audition_added_to_cast", {
        recipient_name: person.name,
        production_name: production.name,
        confirm_by_date: "[date]"
      })
    end

    def generate_default_rejection_email(person, production)
      EmailTemplateService.render("audition_not_cast", {
        recipient_name: person.name,
        production_name: production.name
      })
    end

    def generate_default_invitation_email(person, production, _audition_cycle)
      EmailTemplateService.render_body("audition_invitation", {
        recipient_name: person.name,
        production_name: production.name
      })
    end

    def generate_default_not_invited_email(person, production)
      EmailTemplateService.render_body("audition_not_invited", {
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
      # Check for audition_cycle_id in nested routes first
      cycle_id = params[:audition_cycle_id] || params[:id]

      if cycle_id.present?
        # When coming from /audition_cycles/:id or /audition_cycles/:audition_cycle_id/*
        @audition_cycle = @production.audition_cycles.find_by(id: cycle_id)
        unless @audition_cycle
          redirect_to manage_production_signups_auditions_path(@production), alert: "Audition cycle not found."
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
      params.expect(audition: %i[audition_session_id audition_request_id])
    end

    def redirect_to_archived_summary
      redirect_to manage_production_signups_auditions_cycle_path(@production, @audition_cycle)
    end

    def ensure_user_has_role
      return if Current.user.role_for_production(@production).present?

      redirect_to review_manage_production_signups_auditions_cycle_path(@production, @audition_cycle),
                  alert: "You don't have permission to access this page."
    end
  end
end
