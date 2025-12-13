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
                                   .includes(:location, show_person_role_assignments: :role)
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

      # Build linkage sync info for linked shows
      if @show.linked?
        @linked_shows = @show.linked_shows.includes(:show_person_role_assignments).to_a
        @linkage_sync_info = build_linkage_sync_info(@show, @linked_shows)
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
      cast_members_html = render_to_string(partial: "manage/casting/cast_members_list",
                                           locals: { show: @show,
                                                     availability: @availability })
      roles_html = render_to_string(partial: "manage/casting/roles_list", locals: { show: @show })

      # Calculate progress for the progress bar - count roles with at least one assignment
      roles_with_assignments = @show.show_person_role_assignments.distinct.count(:role_id)
      role_count = @show.available_roles.count
      percentage = role_count.positive? ? (roles_with_assignments.to_f / role_count * 100).round : 0

      # Render finalize section if fully cast
      finalize_section_html = nil
      if percentage == 100
        finalize_section_html = render_finalize_section_html
      end

      render json: {
        cast_members_html: cast_members_html,
        roles_html: roles_html,
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
      cast_members_html = render_to_string(partial: "manage/casting/cast_members_list",
                                           locals: { show: @show,
                                                     availability: @availability })
      roles_html = render_to_string(partial: "manage/casting/roles_list", locals: { show: @show })

      # Calculate progress for the progress bar - count roles with at least one assignment
      roles_with_assignments = @show.show_person_role_assignments.distinct.count(:role_id)
      role_count = @show.available_roles.count
      percentage = role_count.positive? ? (roles_with_assignments.to_f / role_count * 100).round : 0

      # Render finalize section if fully cast
      finalize_section_html = nil
      if percentage == 100
        finalize_section_html = render_finalize_section_html
      end

      render json: {
        cast_members_html: cast_members_html,
        roles_html: roles_html,
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
      cast_members_html = render_to_string(partial: "manage/casting/cast_members_list",
                                           locals: { show: @show,
                                                     availability: @availability })
      roles_html = render_to_string(partial: "manage/casting/roles_list", locals: { show: @show })

      # Calculate progress - count roles with at least one assignment
      roles_with_assignments = @show.show_person_role_assignments.distinct.count(:role_id)
      role_count = @show.available_roles.count
      percentage = role_count.positive? ? (roles_with_assignments.to_f / role_count * 100).round : 0

      # Render finalize section if fully cast
      finalize_section_html = nil
      if percentage == 100
        finalize_section_html = render_finalize_section_html
      end

      render json: {
        success: true,
        vacancy_id: @vacancy.id,
        cast_members_html: cast_members_html,
        roles_html: roles_html,
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

        # Record notifications for this show
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
      @show.reopen_casting!

      redirect_to manage_production_show_cast_path(@production, @show),
                  notice: "Casting reopened. You can now make changes."
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

      # Get this show's assignments
      source_assignments = @show.show_person_role_assignments.includes(:role).to_a

      copied_count = 0
      errors = []

      ActiveRecord::Base.transaction do
        linked_shows.each do |target_show|
          # Get target show's roles by name
          target_roles = target_show.available_roles.index_by(&:name)

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
            else
              errors << "Role '#{source_role_name}' not found on #{target_show.date_and_time.strftime('%b %-d')}"
            end
          end
        end
      end

      if errors.any?
        redirect_to manage_production_show_cast_path(@production, @show),
                    alert: "Cast copied with warnings: #{errors.join(', ')}"
      else
        redirect_to manage_production_show_cast_path(@production, @show),
                    notice: "Cast successfully copied to #{linked_shows.count} linked #{'event'.pluralize(linked_shows.count)}."
      end
    rescue ActiveRecord::RecordInvalid => e
      redirect_to manage_production_show_cast_path(@production, @show),
                  alert: "Failed to copy cast: #{e.message}"
    end

    private

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

    def render_finalize_section_html
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
          "<li><strong>#{info[:show_date]}</strong> - #{info[:show_name]} as <strong>#{info[:role_name]}</strong></li>"
        end.join("\n")

        personalized_body = <<~BODY
          <p>Hi #{person.name},</p>

          <p>You have been cast for the following linked events for #{@production.name}:</p>

          <ul>
          #{shows_list}
          </ul>

          <p>Please confirm your availability for these shows. If you have any scheduling conflicts or questions, contact us as soon as possible.</p>
        BODY

        if notification_type == :removed
          personalized_body = <<~BODY
            <p>Hi #{person.name},</p>

            <p>There has been a change to the casting for #{@production.name}.</p>

            <p>You are no longer cast for the following events:</p>

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
      "Cast Confirmation: #{@production.name} - #{@show.date_and_time.strftime('%B %-d')}"
    end

    def default_cast_email_body
      show_date = @show.date_and_time.strftime("%A, %B %-d at %-l:%M %p")
      <<~BODY
        <p>You have been cast as [Role] for #{@production.name}.</p>

        <p><strong>Show Details:</strong><br>
        Date: #{show_date}<br>
        Role: [Role]</p>

        <p>Please confirm your availability for this show. If you have any scheduling conflicts or questions, contact us as soon as possible.</p>
      BODY
    end

    def default_removed_email_subject
      "Casting Update - #{@production.name} - #{@show.date_and_time.strftime('%B %-d')}"
    end

    def default_removed_email_body
      show_date = @show.date_and_time.strftime("%A, %B %-d at %-l:%M %p")
      <<~BODY
        <p>There has been a change to the casting for #{@production.name} on #{show_date}.</p>

        <p>You are no longer cast for this show.</p>

        <p>If you have any questions, please contact us.</p>
      BODY
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
