# frozen_string_literal: true

module Manage
  class CastingController < Manage::ManageController
    before_action :set_production
    before_action :check_production_access
    before_action :set_show,
                  only: %i[show_cast contact_cast send_cast_email assign_person_to_role remove_person_from_role create_vacancy]

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

      # Preload roles for the production
      @roles = @production.roles.order(:position).to_a
      @roles_count = @roles.size

      # Preload all assignments for this show with their roles
      @assignments = @show.show_person_role_assignments.includes(:role).to_a

      # Build assignment lookup by role_id for the roles_list partial
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

      # Send email to each person
      people_to_email.each do |person|
        Manage::CastingMailer.cast_email(person, @show, @email_draft.title, body_html, Current.user).deliver_later
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

      role = Role.find(params[:role_id])

      # Validate eligibility for restricted roles
      if role.restricted?
        unless role.eligible?(assignable)
          render json: { error: "This cast member is not eligible for this restricted role" }, status: :unprocessable_entity
          return
        end
      end

      # If this role already has someone in it for this show, remove the assignment
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
      role_count = @show.production.roles.count
      percentage = role_count.positive? ? (assignment_count.to_f / role_count * 100).round : 0

      render json: {
        cast_members_html: cast_members_html,
        roles_html: roles_html,
        progress: {
          assignment_count: assignment_count,
          role_count: role_count,
          percentage: percentage
        }
      }
    end

    def remove_person_from_role
      # Support both assignment_id and role_id for removal
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
      role_count = @show.production.roles.count
      percentage = role_count.positive? ? (assignment_count.to_f / role_count * 100).round : 0

      render json: {
        cast_members_html: cast_members_html,
        roles_html: roles_html,
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
      end

      # Re-render the UI
      @availability = build_availability_hash(@show)
      cast_members_html = render_to_string(partial: "manage/casting/cast_members_list",
                                           locals: { show: @show,
                                                     availability: @availability })
      roles_html = render_to_string(partial: "manage/casting/roles_list", locals: { show: @show })

      # Calculate progress
      assignment_count = @show.show_person_role_assignments.count
      role_count = @show.production.roles.count
      percentage = role_count.positive? ? (assignment_count.to_f / role_count * 100).round : 0

      render json: {
        success: true,
        vacancy_id: @vacancy.id,
        cast_members_html: cast_members_html,
        roles_html: roles_html,
        progress: {
          assignment_count: assignment_count,
          role_count: role_count,
          percentage: percentage
        }
      }
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.message }, status: :unprocessable_entity
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

    def email_draft_params
      params.require(:email_draft).permit(:title, :body)
    end
  end
end
