# frozen_string_literal: true

module Manage
  class CastingController < Manage::ManageController
    before_action :set_production
    before_action :check_production_access
    before_action :set_show,
                  only: %i[show_cast contact_cast send_cast_email assign_person_to_role remove_person_from_role create_vacancy finalize_casting reopen_casting copy_cast_to_linked]

    def index
      @upcoming_shows = @production.shows
                                   .where("date_and_time >= ?", Time.current)
                                   .where(casting_enabled: true)
                                   .includes(:location, :custom_roles, show_person_role_assignments: :role)
                                   .order(:date_and_time)

      # Eager load roles for the production (used in cast_card partial)
      @roles = @production.roles.order(:position).to_a
      @roles_count = @roles.size
      @roles_max_updated_at = @roles.map(&:updated_at).compact.max

      # Precompute max assignment updated_at per show to avoid N+1 in cache key
      show_ids = @upcoming_shows.map(&:id)
      @assignments_max_updated_at_by_show = ShowPersonRoleAssignment
        .where(show_id: show_ids)
        .group(:show_id)
        .maximum(:updated_at)

      # Precompute max role updated_at per show for custom roles
      @roles_max_updated_at_by_show = {}
      @upcoming_shows.each do |show|
        if show.use_custom_roles?
          @roles_max_updated_at_by_show[show.id] = show.custom_roles.map(&:updated_at).compact.max
        else
          @roles_max_updated_at_by_show[show.id] = @roles_max_updated_at
        end
      end

      # Preload assignables (people and groups) with their headshots
      all_assignments = @upcoming_shows.flat_map(&:show_person_role_assignments)

      person_ids = all_assignments.select { |a| a.assignable_type == "Person" }.map(&:assignable_id).uniq
      group_ids = all_assignments.select { |a| a.assignable_type == "Group" }.map(&:assignable_id).uniq

      @people_by_id = Person
                      .where(id: person_ids)
                      .includes(profile_headshots: { image_attachment: :blob })
                      .index_by(&:id)

      @groups_by_id = Group
                      .where(id: group_ids)
                      .includes(profile_headshots: { image_attachment: :blob })
                      .index_by(&:id)
    end

    def show_cast
      @availability = build_availability_hash(@show)

      # Use available_roles which respects show.use_custom_roles
      @roles = @show.available_roles.to_a
      @roles_count = @roles.size

      # Preload all assignments for this show with their roles
      @assignments = @show.show_person_role_assignments.includes(:role).to_a

      # Build assignment lookup by role_id
      @assignments_by_role_id = @assignments.group_by(&:role_id)

      # Get assignable IDs for preloading
      person_ids = @assignments.select { |a| a.assignable_type == "Person" }.map(&:assignable_id).uniq
      group_ids = @assignments.select { |a| a.assignable_type == "Group" }.map(&:assignable_id).uniq

      # Preload assignables with headshots
      @people_by_id = Person
                      .where(id: person_ids)
                      .includes(profile_headshots: { image_attachment: :blob })
                      .index_by(&:id)

      @groups_by_id = Group
                      .where(id: group_ids)
                      .includes(profile_headshots: { image_attachment: :blob })
                      .index_by(&:id)

      # For cast_members_list: preload talent pool members with headshots
      @talent_pool = @production.talent_pool

      @pool_people = @talent_pool.people
                     .includes(profile_headshots: { image_attachment: :blob })
                     .to_a

      @pool_groups = @talent_pool.groups
                     .includes(profile_headshots: { image_attachment: :blob })
                     .to_a

      @pool_members = @pool_people + @pool_groups

      # Build set of assigned member keys for quick lookup
      @assigned_member_keys = Set.new(@assignments.map { |a| "#{a.assignable_type}_#{a.assignable_id}" })

      # Build linkage sync info for linked shows (do this before email drafts so they can reference linked shows)
      if @show.linked?
        @linked_shows = @show.linked_shows.includes(:show_person_role_assignments).to_a
        @linkage_sync_info = build_linkage_sync_info(@show, @linked_shows)

        # Build availability for all linked shows (for filtering)
        @linked_availability = build_linked_availability_hash(@linked_shows)
      else
        @linked_shows = []
        @linked_availability = {}
      end

      # Create email drafts for finalization section
      if @show.fully_cast? && !@show.casting_finalized?
        @cast_email_draft = EmailDraft.new(
          title: default_cast_email_subject,
          body: default_cast_email_body
        )
        @removed_email_draft = EmailDraft.new(
          title: default_removed_email_subject,
          body: default_removed_email_body
        )
      end
    end

    def contact_cast
      # Get all entities (people and groups) assigned to roles in this show
      # Note: Can't use .includes(:assignable) on polymorphic associations
      assignments = @show.show_person_role_assignments.includes(:role)

      # Preload people and groups separately
      person_ids = assignments.select { |a| a.assignable_type == "Person" }.map(&:assignable_id)
      group_ids = assignments.select { |a| a.assignable_type == "Group" }.map(&:assignable_id)

      people_by_id = Person.where(id: person_ids).index_by(&:id)
      groups_by_id = Group.includes(:members).where(id: group_ids).index_by(&:id)

      # Store people and groups for display
      @cast_people = []
      @cast_groups = []

      # Collect individual people and groups
      people_for_email = []
      assignments.each do |assignment|
        if assignment.assignable_type == "Person"
          person = people_by_id[assignment.assignable_id]
          if person
            @cast_people << person
            people_for_email << person
          end
        elsif assignment.assignable_type == "Group"
          group = groups_by_id[assignment.assignable_id]
          if group
            @cast_groups << group
            people_for_email.concat(group.members.to_a)
          end
        end
      end

      @cast_people.uniq!
      @cast_groups.uniq!
      @cast_members = people_for_email.uniq.sort_by(&:name)

      # Create a new draft for the form
      @email_draft = EmailDraft.new(emailable: @show)
    end

    def send_cast_email
      @email_draft = EmailDraft.new(email_draft_params.merge(emailable: @show))

      if @email_draft.title.blank? || @email_draft.body.blank?
        redirect_to manage_production_show_contact_cast_path(@production, @show),
                    alert: "Title and message are required"
        return
      end

      # Get all entities (people and groups) assigned to roles in this show
      assignments = @show.show_person_role_assignments

      # Preload people and groups separately
      person_ids = assignments.select { |a| a.assignable_type == "Person" }.map(&:assignable_id).uniq
      group_ids = assignments.select { |a| a.assignable_type == "Group" }.map(&:assignable_id).uniq

      people_by_id = Person.where(id: person_ids).index_by(&:id)
      groups_by_id = Group.includes(group_memberships: :person).where(id: group_ids).index_by(&:id)

      # Count unique cast members (people and groups as entities)
      cast_member_count = person_ids.count + group_ids.count

      # Expand to individual people for email sending (direct assignments + group members with notifications enabled)
      people_to_email = []
      assignments.each do |assignment|
        if assignment.assignable_type == "Person"
          person = people_by_id[assignment.assignable_id]
          people_to_email << person if person
        elsif assignment.assignable_type == "Group"
          group = groups_by_id[assignment.assignable_id]
          if group
            # Add group members who have notifications enabled
            members_with_notifications = group.group_memberships.select(&:notifications_enabled?).map(&:person)
            people_to_email.concat(members_with_notifications)
          end
        end
      end

      people_to_email.uniq!

      # Convert rich text to HTML string for serialization in background jobs
      body_html = @email_draft.body.to_s

      # Create email batch if sending to multiple people
      email_batch = nil
      if people_to_email.size > 1
        email_batch = EmailBatch.create!(
          user: Current.user,
          subject: @email_draft.title,
          recipient_count: people_to_email.size,
          sent_at: Time.current
        )
      end

      # Send email to each person
      people_to_email.each do |person|
        Manage::CastingMailer.cast_email(person, @show, @email_draft.title, body_html, Current.user, email_batch_id: email_batch&.id).deliver_later
      end

      redirect_to manage_production_show_path(@production, @show),
                  notice: "Email sent to #{cast_member_count} cast #{'member'.pluralize(cast_member_count)}"
    end

    def assign_person_to_role
      # Get the assignable entity (person or group) and the role
      if params[:person_id].present?
        assignable = Current.organization.people.find(params[:person_id])
      elsif params[:group_id].present?
        assignable = Current.organization.groups.find(params[:group_id])
      else
        render json: { error: "Must provide person_id or group_id" }, status: :unprocessable_entity
        return
      end

      # Find the role - all roles are now unified in the Role model
      role = Role.find(params[:role_id])

      # Validate eligibility for restricted roles
      if role.restricted? && !role.eligible?(assignable)
        render json: { error: "This cast member is not eligible for this restricted role" }, status: :unprocessable_entity
        return
      end

      # Remove existing assignment for this role
      existing_assignments = @show.show_person_role_assignments.where(role: role)
      existing_assignments.destroy_all if existing_assignments.any?

      # Make the assignment
      assignment = @show.show_person_role_assignments.find_or_initialize_by(assignable: assignable, role: role)

      assignment.save!

      # Generate the HTML to return - pass availability data
      @availability = build_availability_hash(@show)

      # Build linkage sync info for linked shows
      sync_info = nil
      linked_shows = []
      is_linked = @show.linked?
      if is_linked
        linked_shows = @show.linked_shows.to_a
        sync_info = build_linkage_sync_info(@show, linked_shows)
      end

      cast_members_html = render_to_string(partial: "manage/casting/cast_members_list",
                                           locals: { show: @show,
                                                     availability: @availability })
      roles_html = render_to_string(partial: "manage/casting/roles_list", locals: { show: @show, sync_info: sync_info })

      # Calculate progress for the progress bar - count roles with at least one assignment
      roles_with_assignments = @show.show_person_role_assignments.distinct.count(:role_id)
      role_count = @show.available_roles.count
      percentage = role_count.positive? ? (roles_with_assignments.to_f / role_count * 100).round : 0
      fully_cast = percentage == 100

      # Render linkage sync section if this is a linked show
      linkage_sync_html = nil
      if is_linked && sync_info.present?
        linkage_sync_html = render_to_string(
          partial: "manage/casting/linkage_sync_section",
          locals: {
            show: @show,
            linked_shows: linked_shows,
            sync_info: sync_info,
            production: @production,
            fully_cast: fully_cast
          }
        )
      end

      # Render finalize section if fully cast AND (not linked OR in sync)
      finalize_section_html = nil
      all_in_sync = sync_info.present? ? sync_info[:all_in_sync] : true
      can_finalize = fully_cast && (!is_linked || all_in_sync)

      if can_finalize
        finalize_section_html = render_finalize_section_html(linked_shows)
      end

      render json: {
        cast_members_html: cast_members_html,
        roles_html: roles_html,
        linkage_sync_html: linkage_sync_html,
        finalize_section_html: finalize_section_html,
        progress: {
          assignment_count: roles_with_assignments,
          role_count: role_count,
          percentage: percentage
        }
      }
    end

    def remove_person_from_role
      # Support assignment_id or role_id for removal
      removed_assignable_type = nil
      removed_assignable_id = nil

      if params[:assignment_id]
        assignment = @show.show_person_role_assignments.find(params[:assignment_id])
        if assignment
          removed_assignable_type = assignment.assignable_type
          removed_assignable_id = assignment.assignable_id
        end
        assignment&.destroy!
      elsif params[:role_id]
        # Get the assignable before removing (there should only be one per role)
        assignment = @show.show_person_role_assignments.where(role_id: params[:role_id]).first
        if assignment
          removed_assignable_type = assignment.assignable_type
          removed_assignable_id = assignment.assignable_id
        end
        # Remove all assignments for this role
        @show.show_person_role_assignments.where(role_id: params[:role_id]).destroy_all
      end

      # Generate the HTML to return - pass availability data
      @availability = build_availability_hash(@show)

      # Build linkage sync info for linked shows
      sync_info = nil
      linked_shows = []
      is_linked = @show.linked?
      if is_linked
        linked_shows = @show.linked_shows.to_a
        sync_info = build_linkage_sync_info(@show, linked_shows)
      end

      cast_members_html = render_to_string(partial: "manage/casting/cast_members_list",
                                           locals: { show: @show,
                                                     availability: @availability })
      roles_html = render_to_string(partial: "manage/casting/roles_list", locals: { show: @show, sync_info: sync_info })

      # Calculate progress for the progress bar - count roles with at least one assignment
      roles_with_assignments = @show.show_person_role_assignments.distinct.count(:role_id)
      role_count = @show.available_roles.count
      percentage = role_count.positive? ? (roles_with_assignments.to_f / role_count * 100).round : 0
      fully_cast = percentage == 100

      # Render linkage sync section if this is a linked show
      linkage_sync_html = nil
      if is_linked && sync_info.present?
        linkage_sync_html = render_to_string(
          partial: "manage/casting/linkage_sync_section",
          locals: {
            show: @show,
            linked_shows: linked_shows,
            sync_info: sync_info,
            production: @production,
            fully_cast: fully_cast
          }
        )
      end

      # Render finalize section if fully cast AND (not linked OR in sync)
      finalize_section_html = nil
      all_in_sync = sync_info.present? ? sync_info[:all_in_sync] : true
      can_finalize = fully_cast && (!is_linked || all_in_sync)

      if can_finalize
        finalize_section_html = render_finalize_section_html(linked_shows)
      end

      render json: {
        cast_members_html: cast_members_html,
        roles_html: roles_html,
        linkage_sync_html: linkage_sync_html,
        finalize_section_html: finalize_section_html,
        assignable_type: removed_assignable_type,
        assignable_id: removed_assignable_id,
        person_id: removed_assignable_id, # Backward compatibility
        progress: {
          assignment_count: roles_with_assignments,
          role_count: role_count,
          percentage: percentage
        }
      }
    end

    # Create a vacancy from an existing role assignment
    # This removes the assignment and creates an open vacancy
    def create_vacancy
      role = @production.roles.find(params[:role_id])
      assignment = @show.show_person_role_assignments.find_by(role: role)

      unless assignment
        render json: { error: "No assignment found for this role" }, status: :unprocessable_entity
        return
      end

      # Only Person assignables can be tracked as vacated_by
      vacated_by = assignment.assignable_type == "Person" ? assignment.assignable : nil
      reason = params[:reason]

      ActiveRecord::Base.transaction do
        # Create the vacancy
        @vacancy = RoleVacancy.create!(
          show: @show,
          role: role,
          vacated_by: vacated_by,
          vacated_at: Time.current,
          reason: reason,
          status: :open,
          created_by_id: Current.person&.id
        )

        # Remove the assignment
        assignment.destroy!

        # Unfinalize casting since we now have an open role
        @show.reopen_casting! if @show.casting_finalized?
      end

      # Re-render the UI
      @availability = build_availability_hash(@show)

      # Build linkage sync info for linked shows
      sync_info = nil
      linked_shows = []
      is_linked = @show.linked?
      if is_linked
        linked_shows = @show.linked_shows.to_a
        sync_info = build_linkage_sync_info(@show, linked_shows)
      end

      cast_members_html = render_to_string(partial: "manage/casting/cast_members_list",
                                           locals: { show: @show,
                                                     availability: @availability })
      roles_html = render_to_string(partial: "manage/casting/roles_list", locals: { show: @show, sync_info: sync_info })

      # Calculate progress - count roles with at least one assignment
      roles_with_assignments = @show.show_person_role_assignments.distinct.count(:role_id)
      role_count = @show.available_roles.count
      percentage = role_count.positive? ? (roles_with_assignments.to_f / role_count * 100).round : 0
      fully_cast = percentage == 100

      # Render linkage sync section if this is a linked show
      linkage_sync_html = nil
      if is_linked && sync_info.present?
        linkage_sync_html = render_to_string(
          partial: "manage/casting/linkage_sync_section",
          locals: {
            show: @show,
            linked_shows: linked_shows,
            sync_info: sync_info,
            production: @production,
            fully_cast: fully_cast
          }
        )
      end

      # Render finalize section if fully cast AND (not linked OR in sync)
      finalize_section_html = nil
      all_in_sync = sync_info.present? ? sync_info[:all_in_sync] : true
      can_finalize = fully_cast && (!is_linked || all_in_sync)

      if can_finalize
        finalize_section_html = render_finalize_section_html(linked_shows)
      end

      render json: {
        success: true,
        vacancy_id: @vacancy.id,
        cast_members_html: cast_members_html,
        roles_html: roles_html,
        linkage_sync_html: linkage_sync_html,
        finalize_section_html: finalize_section_html,
        progress: {
          assignment_count: roles_with_assignments,
          role_count: role_count,
          percentage: percentage
        }
      }
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def finalize_casting
      unless @show.fully_cast?
        redirect_to manage_production_show_cast_path(@production, @show),
                    alert: "Cannot finalize casting until all roles are filled."
        return
      end

      # For linked shows, gather all shows to finalize together
      shows_to_finalize = [ @show ]
      if @show.linked?
        linked_shows = @show.linked_shows.to_a
        sync_info = build_linkage_sync_info(@show, linked_shows)

        unless sync_info[:all_in_sync]
          redirect_to manage_production_show_cast_path(@production, @show),
                      alert: "Cannot finalize casting: linked events are not in sync. Please copy cast to linked events first."
          return
        end

        # Add linked shows that aren't already finalized
        linked_shows.each do |linked_show|
          shows_to_finalize << linked_show unless linked_show.casting_finalized?
        end
      end

      # Get email content from form params (rich text uses email_draft nested params)
      cast_draft_params = params[:cast_email_draft] || {}
      removed_draft_params = params[:removed_email_draft] || {}

      cast_subject = cast_draft_params[:title].presence || default_cast_email_subject
      cast_body = cast_draft_params[:body].to_s.presence || default_cast_email_body
      removed_subject = removed_draft_params[:title].presence || default_removed_email_subject
      removed_body = removed_draft_params[:body].to_s.presence || default_removed_email_body

      # Collect all unique assignables across all shows to finalize
      # Each person should only get ONE email listing ALL their assignments across linked shows
      cast_notifications_by_person = {}  # person => [{show:, role:, assignable:}, ...]
      removed_notifications_by_person = {} # person => [{show:, role:, assignable:}, ...]

      shows_to_finalize.each do |show|
        # Get current cast members who need notification
        unnotified_assignments = show.unnotified_cast_members
        unnotified_assignments.each do |a|
          next unless a.role  # Skip orphaned assignments

          # For groups, get all members; for people, just the person
          recipients = a.assignable.is_a?(Group) ? a.assignable.group_memberships.select(&:notifications_enabled?).map(&:person) : [ a.assignable ]

          recipients.each do |person|
            next unless person.email.present?
            cast_notifications_by_person[person] ||= []
            cast_notifications_by_person[person] << { show: show, role: a.role, assignable: a.assignable }
          end
        end

        # Get removed cast members who need notification
        removed_members = show.removed_cast_members
        removed_members.each do |assignable|
          prev_notification = show.show_cast_notifications
                                  .cast_notifications
                                  .where(assignable: assignable)
                                  .order(notified_at: :desc)
                                  .first
          next unless prev_notification&.role

          recipients = assignable.is_a?(Group) ? assignable.group_memberships.select(&:notifications_enabled?).map(&:person) : [ assignable ]

          recipients.each do |person|
            next unless person.email.present?
            removed_notifications_by_person[person] ||= []
            removed_notifications_by_person[person] << { show: show, role: prev_notification.role, assignable: assignable }
          end
        end
      end

      # Send consolidated emails for cast members
      cast_notifications_by_person.each do |person, assignments|
        send_consolidated_cast_email(person, assignments, cast_body, cast_subject, :cast)
      end

      # Send consolidated emails for removed members
      removed_notifications_by_person.each do |person, assignments|
        send_consolidated_cast_email(person, assignments, removed_body, removed_subject, :removed)
      end

      # Finalize all shows and record notifications
      shows_to_finalize.each do |show|
        # Close any open vacancies
        show.role_vacancies.open.update_all(status: :filled, filled_at: Time.current)

        # Record notifications for current cast members
        show.unnotified_cast_members.each do |a|
          next unless a.role
          show.show_cast_notifications.find_or_initialize_by(
            assignable: a.assignable,
            role: a.role
          ).update!(
            notification_type: :cast,
            notified_at: Time.current,
            email_body: cast_body
          )
        end

        # Remove notification records for people who are no longer in the cast
        # This prevents them from showing up as "removed" again after reopening
        show.removed_cast_members.each do |assignable|
          show.show_cast_notifications.where(
            assignable: assignable,
            notification_type: :cast
          ).destroy_all
        end

        # Mark casting as finalized
        show.finalize_casting!
      end

      finalized_count = shows_to_finalize.count
      if finalized_count > 1
        redirect_to manage_production_show_cast_path(@production, @show),
                    notice: "Casting finalized for #{finalized_count} linked events and notifications sent!"
      else
        redirect_to manage_production_show_cast_path(@production, @show),
                    notice: "Casting finalized and notifications sent!"
      end
    end

    def reopen_casting
      # Reopen this show and all linked shows
      shows_to_reopen = [ @show ]
      if @show.linked?
        shows_to_reopen += @show.linked_shows.select(&:casting_finalized?)
      end

      shows_to_reopen.each(&:reopen_casting!)

      if shows_to_reopen.count > 1
        redirect_to manage_production_show_cast_path(@production, @show),
                    notice: "Casting reopened for #{shows_to_reopen.count} linked events. You can now make changes."
      else
        redirect_to manage_production_show_cast_path(@production, @show),
                    notice: "Casting reopened. You can now make changes."
      end
    end

    def copy_cast_to_linked
      unless @show.linked?
        redirect_to manage_production_show_cast_path(@production, @show),
                    alert: "This event is not linked to any other events."
        return
      end

      linked_shows = @show.linked_shows.to_a
      if linked_shows.empty?
        redirect_to manage_production_show_cast_path(@production, @show),
                    alert: "No linked events found."
        return
      end

      # Get source show's roles and assignments
      source_roles = @show.available_roles.to_a
      source_assignments = @show.show_person_role_assignments.includes(:role).to_a
      source_using_custom = @show.use_custom_roles?

      copied_count = 0

      ActiveRecord::Base.transaction do
        linked_shows.each do |target_show|
          # First, sync roles
          sync_roles_to_show(target_show, source_roles, source_using_custom)

          # Get target show's roles by name (after syncing)
          target_roles = target_show.available_roles.reload.index_by(&:name)

          # Clear existing assignments on target show
          target_show.show_person_role_assignments.destroy_all

          # Copy assignments from source to target
          source_assignments.each do |source_assignment|
            source_role_name = source_assignment.role&.name
            next unless source_role_name

            target_role = target_roles[source_role_name]
            if target_role
              target_show.show_person_role_assignments.create!(
                role: target_role,
                assignable_type: source_assignment.assignable_type,
                assignable_id: source_assignment.assignable_id
              )
              copied_count += 1
            end
          end
        end
      end

      redirect_to manage_production_show_cast_path(@production, @show),
                  notice: "Roles and cast successfully synced to #{linked_shows.count} linked #{'event'.pluralize(linked_shows.count)}."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to manage_production_show_cast_path(@production, @show),
                  alert: "Failed to sync: #{e.message}"
    end

    private

    # Sync roles from source to target show
    def sync_roles_to_show(target_show, source_roles, source_using_custom)
      # If source uses production roles and target also uses production roles, they're already in sync
      if !source_using_custom && !target_show.use_custom_roles?
        return
      end

      # Target needs to use custom roles to match source
      target_show.update!(use_custom_roles: true)

      # Get existing custom roles on target
      existing_roles = target_show.custom_roles.index_by(&:name)
      source_role_names = source_roles.map(&:name).to_set

      # Remove custom roles that don't exist in source (and their assignments)
      existing_roles.each do |name, role|
        unless source_role_names.include?(name)
          role.destroy!
        end
      end

      # Add or update roles to match source
      source_roles.each do |source_role|
        target_role = existing_roles[source_role.name]
        if target_role
          # Update existing role
          target_role.update!(
            position: source_role.position,
            restricted: source_role.restricted
          )

          # Sync eligibilities if restricted
          if source_role.restricted?
            target_role.role_eligibilities.destroy_all
            source_role.role_eligibilities.each do |eligibility|
              target_role.role_eligibilities.create!(
                member_type: eligibility.member_type,
                member_id: eligibility.member_id
              )
            end
          else
            target_role.role_eligibilities.destroy_all
          end
        else
          # Create new role
          new_role = target_show.custom_roles.create!(
            name: source_role.name,
            position: source_role.position,
            restricted: source_role.restricted,
            production: target_show.production
          )

          # Copy eligibilities if restricted
          if source_role.restricted?
            source_role.role_eligibilities.each do |eligibility|
              new_role.role_eligibilities.create!(
                member_type: eligibility.member_type,
                member_id: eligibility.member_id
              )
            end
          end
        end
      end
    end

    def set_production
      @production = Current.organization.productions.find(params.require(:production_id))
    end

    def set_show
      @show = @production.shows.find(params[:show_id])
    end

    def build_availability_hash(show)
      availability = {}
      ShowAvailability.where(show_id: show.id).each do |show_availability|
        key = "#{show_availability.available_entity_type}_#{show_availability.available_entity_id}"
        availability[key] = show_availability
        # Also store by ID for backward compatibility (assumes Person if no type prefix)
        if show_availability.available_entity_type == "Person"
          availability[show_availability.available_entity_id] = show_availability
        end
      end
      availability
    end

    # Build a hash of availability across all linked shows
    # Returns { "Person_123" => { total: 3, available: 2, shows: [{ show_id: 1, available: true }, ...] } }
    def build_linked_availability_hash(linked_shows)
      return {} if linked_shows.empty?

      result = {}
      show_ids = linked_shows.map(&:id)

      # Load all availability records for linked shows
      ShowAvailability.where(show_id: show_ids).each do |avail|
        key = "#{avail.available_entity_type}_#{avail.available_entity_id}"
        result[key] ||= { total: linked_shows.count, available: 0, shows: [] }
        result[key][:shows] << { show_id: avail.show_id, available: avail.available? }
        result[key][:available] += 1 if avail.available?
      end

      # Ensure all members have entries even if they have no availability records
      linked_shows.count.tap do |total|
        result.each do |_key, data|
          data[:total] = total
        end
      end

      result
    end

    def render_finalize_section_html(linked_shows = nil)
      # Set @linked_shows so email methods can use it
      @linked_shows = linked_shows || []

      # Create email drafts for the finalize section
      cast_email_draft = EmailDraft.new(
        title: default_cast_email_subject,
        body: default_cast_email_body
      )
      removed_email_draft = EmailDraft.new(
        title: default_removed_email_subject,
        body: default_removed_email_body
      )

      render_to_string(
        partial: "manage/casting/finalize_section",
        locals: {
          show: @show,
          production: @production,
          linked_shows: @linked_shows,
          cast_email_draft: cast_email_draft,
          removed_email_draft: removed_email_draft
        }
      )
    end

    def email_draft_params
      params.require(:email_draft).permit(:title, :body)
    end

    def send_casting_emails(assignables_with_roles, email_body, subject, notification_type)
      assignables_with_roles.each do |assignable, role|
        # For groups, email all members with notifications enabled
        recipients = if assignable.is_a?(Group)
                       assignable.group_memberships.select(&:notifications_enabled?).map(&:person)
        else
                       [ assignable ]
        end

        recipients.each do |person|
          next unless person.email.present?

          # Personalize the email body
          personalized_body = email_body.gsub("[Name]", person.name)
                                         .gsub("[Role]", role.name)
                                         .gsub("[Show]", @show.secondary_name.presence || @show.event_type.titleize)
                                         .gsub("[Date]", @show.date_and_time.strftime("%A, %B %-d at %-l:%M %p"))
                                         .gsub("[Production]", @production.name)

          if notification_type == :cast
            Manage::CastingMailer.cast_notification(person, @show, personalized_body, subject).deliver_later
          else
            Manage::CastingMailer.removed_notification(person, @show, personalized_body, subject).deliver_later
          end
        end

        # Record the notification (update existing or create new)
        notification = @show.show_cast_notifications.find_or_initialize_by(
          assignable: assignable,
          role: role
        )
        notification.update!(
          notification_type: notification_type,
          notified_at: Time.current,
          email_body: email_body
        )
      end
    end

    # Send a single consolidated email to a person with all their assignments across linked shows
    def send_consolidated_cast_email(person, assignments, email_body, subject, notification_type)
      # Build a list of all shows and roles for this person
      shows_info = assignments.map do |a|
        show = a[:show]
        role = a[:role]
        {
          show_name: show.secondary_name.presence || show.event_type.titleize,
          show_date: show.date_and_time.strftime("%A, %B %-d at %-l:%M %p"),
          role_name: role.name
        }
      end

      # For the personalized body, if there are multiple shows, create a list
      if shows_info.size == 1
        # Single show - use the standard replacement
        info = shows_info.first
        personalized_body = email_body.gsub("[Name]", person.name)
                                       .gsub("[Role]", info[:role_name])
                                       .gsub("[Show]", info[:show_name])
                                       .gsub("[Date]", info[:show_date])
                                       .gsub("[Production]", @production.name)
      else
        # Multiple shows - build a consolidated message
        shows_list = shows_info.map do |info|
          "<li>#{info[:show_date]}: #{info[:show_name]}</li>"
        end.join("\n")

        personalized_body = <<~BODY
          <p>You have been cast as #{shows_info.first[:role_name]} in the following shows/events for #{@production.name}:</p>

          <ul>
          #{shows_list}
          </ul>

          <p>Please let us know if you have any scheduling conflicts or questions.</p>
        BODY

        if notification_type == :removed
          personalized_body = <<~BODY
            <p>There has been a change to the casting for #{@production.name}.</p>

            <p>You are no longer cast in the following shows/events:</p>

            <ul>
            #{shows_list}
            </ul>

            <p>If you have any questions, please contact us.</p>
          BODY
        end
      end

      # Use the first show as the primary for the mailer (it needs a show reference)
      primary_show = assignments.first[:show]

      if notification_type == :cast
        Manage::CastingMailer.cast_notification(person, primary_show, personalized_body, subject).deliver_later
      else
        Manage::CastingMailer.removed_notification(person, primary_show, personalized_body, subject).deliver_later
      end
    end

    def default_cast_email_subject
      if @show.linked? && @linked_shows.present? && @linked_shows.any?
        all_shows = [ @show ] + @linked_shows
        dates = all_shows.sort_by(&:date_and_time).map { |s| s.date_and_time.strftime("%B %-d") }.uniq
        if dates.count > 2
          "Cast Confirmation: #{@production.name} - #{dates.first} - #{dates.last}"
        else
          "Cast Confirmation: #{@production.name} - #{dates.join(' & ')}"
        end
      else
        "Cast Confirmation: #{@production.name} - #{@show.date_and_time.strftime('%B %-d')}"
      end
    end

    def default_cast_email_body
      if @show.linked? && @linked_shows.present? && @linked_shows.any?
        all_shows = [ @show ] + @linked_shows
        sorted_shows = all_shows.sort_by(&:date_and_time)
        show_list = sorted_shows.map do |s|
          show_name = s.secondary_name.presence || s.event_type.titleize
          date = s.date_and_time.strftime("%A, %B %-d at %-l:%M %p")
          "<li>#{date}: #{show_name}</li>"
        end.join("\n")

        <<~BODY
          <p>You have been cast in the following shows/events for #{@production.name}:</p>

          <ul>
          #{show_list}
          </ul>

          <p>Please let us know if you have any scheduling conflicts or questions.</p>
        BODY
      else
        show_name = @show.secondary_name.presence || @show.event_type.titleize
        show_date = @show.date_and_time.strftime("%A, %B %-d at %-l:%M %p")
        <<~BODY
          <p>You have been cast for #{@production.name}:</p>

          <ul>
          <li>#{show_date}: #{show_name}</li>
          </ul>

          <p>Please let us know if you have any scheduling conflicts or questions.</p>
        BODY
      end
    end

    def default_removed_email_subject
      if @show.linked? && @linked_shows.present? && @linked_shows.any?
        all_shows = [ @show ] + @linked_shows
        dates = all_shows.sort_by(&:date_and_time).map { |s| s.date_and_time.strftime("%B %-d") }.uniq
        if dates.count > 2
          "Casting Update - #{@production.name} - #{dates.first} - #{dates.last}"
        else
          "Casting Update - #{@production.name} - #{dates.join(' & ')}"
        end
      else
        "Casting Update - #{@production.name} - #{@show.date_and_time.strftime('%B %-d')}"
      end
    end

    def default_removed_email_body
      if @show.linked? && @linked_shows.present? && @linked_shows.any?
        all_shows = [ @show ] + @linked_shows
        sorted_shows = all_shows.sort_by(&:date_and_time)
        show_list = sorted_shows.map do |s|
          show_name = s.secondary_name.presence || s.event_type.titleize
          date = s.date_and_time.strftime("%A, %B %-d at %-l:%M %p")
          "<li>#{date}: #{show_name}</li>"
        end.join("\n")

        <<~BODY
          <p>There has been a change to the casting for #{@production.name}.</p>

          <p>You are no longer cast in the following shows/events:</p>
          <ul>
          #{show_list}
          </ul>

          <p>If you have any questions, please contact us.</p>
        BODY
      else
        show_name = @show.secondary_name.presence || @show.event_type.titleize
        show_date = @show.date_and_time.strftime("%A, %B %-d at %-l:%M %p")
        <<~BODY
          <p>There has been a change to the casting for #{@production.name}.</p>

          <p>You are no longer cast for:</p>
          <ul>
          <li>#{show_date}: #{show_name}</li>
          </ul>

          <p>If you have any questions, please contact us.</p>
        BODY
      end
    end

    # Build sync info comparing this show's cast with linked shows
    def build_linkage_sync_info(show, linked_shows)
      current_roles = show.available_roles.pluck(:id, :name).to_h

      sync_info = {
        all_in_sync: true,
        roles_match: true,
        casts_match: true,
        linked_shows_info: [],
        current_role_names: current_roles.values.sort
      }

      linked_shows.each do |linked_show|
        linked_roles = linked_show.available_roles.pluck(:id, :name).to_h

        # Check if roles match (by name, since IDs will differ for custom roles)
        roles_match = current_roles.values.sort == linked_roles.values.sort

        # Check if casts match (comparing assignable keys, normalized by role name)
        # Build a map of role_name => [assignable_key, ...] for comparison
        current_cast_by_role = {}
        show.show_person_role_assignments.each do |a|
          role_name = current_roles[a.role_id]
          next unless role_name
          current_cast_by_role[role_name] ||= []
          current_cast_by_role[role_name] << "#{a.assignable_type}_#{a.assignable_id}"
        end

        linked_cast_by_role = {}
        linked_show.show_person_role_assignments.each do |a|
          role_name = linked_roles[a.role_id]
          next unless role_name
          linked_cast_by_role[role_name] ||= []
          linked_cast_by_role[role_name] << "#{a.assignable_type}_#{a.assignable_id}"
        end

        # Normalize for comparison (sort the arrays)
        current_cast_by_role.transform_values!(&:sort)
        linked_cast_by_role.transform_values!(&:sort)

        casts_match = current_cast_by_role == linked_cast_by_role

        show_info = {
          show: linked_show,
          roles_match: roles_match,
          casts_match: casts_match,
          in_sync: roles_match && casts_match,
          role_names: linked_roles.values.sort,
          cast_count: linked_show.show_person_role_assignments.count,
          fully_cast: linked_show.fully_cast?
        }

        sync_info[:linked_shows_info] << show_info
        sync_info[:all_in_sync] = false unless show_info[:in_sync]
        sync_info[:roles_match] = false unless roles_match
        sync_info[:casts_match] = false unless casts_match
      end

      sync_info
    end
  end
end
