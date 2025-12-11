# frozen_string_literal: true

module Manage
  class CastingController < Manage::ManageController
    before_action :set_production
    before_action :check_production_access
    before_action :set_show,
                  only: %i[show_cast contact_cast send_cast_email assign_person_to_role remove_person_from_role create_vacancy finalize_casting reopen_casting]

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
      @talent_pools = @production.talent_pools.to_a
      talent_pool_ids = @talent_pools.map(&:id)

      @pool_people = Person
                     .joins(:talent_pool_memberships)
                     .where(talent_pool_memberships: { talent_pool_id: talent_pool_ids })
                     .includes(profile_headshots: { image_attachment: :blob })
                     .distinct
                     .to_a

      @pool_groups = Group
                     .joins(:talent_pool_memberships)
                     .where(talent_pool_memberships: { talent_pool_id: talent_pool_ids })
                     .includes(profile_headshots: { image_attachment: :blob })
                     .distinct
                     .to_a

      # Build lookup for talent pool memberships
      memberships = TalentPoolMembership.where(talent_pool_id: talent_pool_ids).to_a
      @members_by_pool_id = {}
      @talent_pools.each { |tp| @members_by_pool_id[tp.id] = [] }

      people_by_id_for_pools = @pool_people.index_by(&:id)
      groups_by_id_for_pools = @pool_groups.index_by(&:id)

      memberships.each do |m|
        member = if m.member_type == "Person"
                   people_by_id_for_pools[m.member_id]
        else
                   groups_by_id_for_pools[m.member_id]
        end
        @members_by_pool_id[m.talent_pool_id] << member if member
      end

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

      # Calculate progress for the progress bar
      assignment_count = @show.show_person_role_assignments.count
      role_count = @show.available_roles.count
      percentage = role_count.positive? ? (assignment_count.to_f / role_count * 100).round : 0

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
          assignment_count: assignment_count,
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

      # Calculate progress for the progress bar
      assignment_count = @show.show_person_role_assignments.count
      role_count = @show.available_roles.count
      percentage = role_count.positive? ? (assignment_count.to_f / role_count * 100).round : 0

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
          assignment_count: assignment_count,
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

      # Calculate progress
      assignment_count = @show.show_person_role_assignments.count
      role_count = @show.available_roles.count
      percentage = role_count.positive? ? (assignment_count.to_f / role_count * 100).round : 0

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
          assignment_count: assignment_count,
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

      # Get email content from form params (rich text uses email_draft nested params)
      cast_draft_params = params[:cast_email_draft] || {}
      removed_draft_params = params[:removed_email_draft] || {}

      cast_subject = cast_draft_params[:title].presence || default_cast_email_subject
      cast_body = cast_draft_params[:body].to_s.presence || default_cast_email_body
      removed_subject = removed_draft_params[:title].presence || default_removed_email_subject
      removed_body = removed_draft_params[:body].to_s.presence || default_removed_email_body

      # Get current cast members who need notification
      unnotified_assignments = @show.unnotified_cast_members
      cast_to_notify = unnotified_assignments.map { |a| [ a.assignable, a.role ] }

      # Get removed cast members who need notification
      removed_members = @show.removed_cast_members
      # For removed members, we need to find what role they were previously notified for
      removed_to_notify = removed_members.map do |assignable|
        # Find the most recent cast notification for this assignable
        prev_notification = @show.show_cast_notifications
                                  .cast_notifications
                                  .where(assignable: assignable)
                                  .order(notified_at: :desc)
                                  .first
        [ assignable, prev_notification&.role ]
      end.compact

      # Send cast notification emails
      if cast_to_notify.any?
        send_casting_emails(cast_to_notify, cast_body, cast_subject, :cast)
      end

      # Send removed notification emails
      if removed_to_notify.any?
        send_casting_emails(removed_to_notify, removed_body, removed_subject, :removed)
      end

      # Close any open vacancies since all roles are now filled
      @show.role_vacancies.open.update_all(status: :filled, filled_at: Time.current)

      # Mark casting as finalized
      @show.finalize_casting!

      redirect_to manage_production_show_cast_path(@production, @show),
                  notice: "Casting finalized and notifications sent!"
    end

    def reopen_casting
      @show.reopen_casting!

      redirect_to manage_production_show_cast_path(@production, @show),
                  notice: "Casting reopened. You can now make changes."
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
  end
end
