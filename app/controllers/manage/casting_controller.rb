# frozen_string_literal: true

module Manage
  class CastingController < Manage::ManageController
    before_action :set_production, except: [ :org_index ]
    before_action :check_production_access, except: [ :org_index ]
    before_action :check_not_third_party, except: [ :org_index ]
    before_action :set_show,
                  only: %i[show_cast assign_person_to_role assign_guest_to_role remove_person_from_role replace_assignment create_vacancy finalize_casting reopen_casting copy_cast_to_linked]

    # Org-level casting index (moved from org_casting_controller)
    def org_index
      # Store the shows filter (default to upcoming)
      @filter = params[:filter] || session[:casting_filter] || "upcoming"
      session[:casting_filter] = @filter

      # Hide canceled events toggle (default: true - hide canceled)
      @hide_canceled = if params[:hide_canceled].present?
        params[:hide_canceled] == "true"
      else
        session[:casting_hide_canceled].nil? ? true : session[:casting_hide_canceled]
      end
      session[:casting_hide_canceled] = @hide_canceled

      # Get all in-house productions for the organization (exclude third-party)
      @productions = Current.organization.productions.type_in_house.order(:name)

      # Get shows with casting enabled across all in-house productions
      base_shows = Show.where(production: @productions, casting_enabled: true)
                       .includes(:production, :location, :custom_roles, show_person_role_assignments: :role)

      # Apply canceled filter
      base_shows = base_shows.where(canceled: false) if @hide_canceled

      case @filter
      when "past"
        @shows = base_shows.where("date_and_time < ?", Time.current).order(date_and_time: :desc)
      else
        @filter = "upcoming"
        @shows = base_shows.where("date_and_time >= ?", Time.current).order(:date_and_time)
      end

      # Load into memory
      @shows = @shows.to_a

      # Preload roles per production
      @roles_by_production = {}
      @productions.each do |production|
        @roles_by_production[production.id] = production.roles.order(:position).to_a
      end

      # Precompute max assignment updated_at per show
      show_ids = @shows.map(&:id)
      @assignments_max_updated_at_by_show = ShowPersonRoleAssignment
        .where(show_id: show_ids)
        .group(:show_id)
        .maximum(:updated_at)

      # Precompute max role updated_at per show for custom roles
      @roles_max_updated_at_by_show = {}
      @shows.each do |show|
        if show.use_custom_roles?
          @roles_max_updated_at_by_show[show.id] = show.custom_roles.map(&:updated_at).compact.max
        else
          roles = @roles_by_production[show.production_id] || []
          @roles_max_updated_at_by_show[show.id] = roles.map(&:updated_at).compact.max
        end
      end

      # Preload assignables (people and groups) with their headshots
      all_assignments = @shows.flat_map(&:show_person_role_assignments)

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

      # Load cancelled vacancies for all shows
      @cancelled_vacancies_by_show = {}
      @shows.each do |show|
        @cancelled_vacancies_by_show[show.id] = show.cancelled_vacancies_by_assignment
      end

      # Load open vacancies for non-linked shows
      @open_vacancies_by_show = {}
      @shows.each do |show|
        next if show.linked?
        open_vacancies = show.role_vacancies.open.includes(:role, :vacated_by).to_a
        @open_vacancies_by_show[show.id] = open_vacancies.group_by(&:role_id)
      end

      # Load sign-up registrations for shows with linked sign-up forms
      sign_up_registrations = SignUpRegistration
        .joins(sign_up_slot: :sign_up_form_instance)
        .where(sign_up_form_instances: { show_id: show_ids })
        .where(status: %w[confirmed waitlisted])
        .includes(:person, person: { profile_headshots: { image_attachment: :blob } }, sign_up_slot: { sign_up_form_instance: :sign_up_form })
        .to_a

      @sign_up_registrations_by_show = sign_up_registrations.group_by { |r| r.sign_up_slot.sign_up_form_instance.show_id }
    end

    def index
      # Store the shows filter (default to upcoming)
      @filter = params[:filter] || session[:casting_filter] || "upcoming"
      session[:casting_filter] = @filter

      # Hide canceled shows toggle (default: true - hide canceled)
      @hide_canceled = if params[:hide_canceled].present?
        params[:hide_canceled] == "true"
      else
        session[:casting_hide_canceled].nil? ? true : session[:casting_hide_canceled]
      end
      session[:casting_hide_canceled] = @hide_canceled

      base_shows = @production.shows
                              .where(casting_enabled: true)
                              .includes(:location, :custom_roles, show_person_role_assignments: :role)

      # Apply canceled filter
      base_shows = base_shows.where(canceled: false) if @hide_canceled

      case @filter
      when "past"
        @shows = base_shows.where("date_and_time < ?", Time.current).order(date_and_time: :desc)
      else
        @filter = "upcoming"
        @shows = base_shows.where("date_and_time >= ?", Time.current).order(:date_and_time)
      end

      # Eager load roles for the production (used in cast_card partial)
      @roles = @production.roles.order(:position).to_a
      @roles_count = @roles.size
      @roles_max_updated_at = @roles.map(&:updated_at).compact.max

      # Precompute max assignment updated_at per show to avoid N+1 in cache key
      show_ids = @shows.map(&:id)
      @assignments_max_updated_at_by_show = ShowPersonRoleAssignment
        .where(show_id: show_ids)
        .group(:show_id)
        .maximum(:updated_at)

      # Precompute max role updated_at per show for custom roles
      @roles_max_updated_at_by_show = {}
      @shows.each do |show|
        if show.use_custom_roles?
          @roles_max_updated_at_by_show[show.id] = show.custom_roles.map(&:updated_at).compact.max
        else
          @roles_max_updated_at_by_show[show.id] = @roles_max_updated_at
        end
      end

      # Preload assignables (people and groups) with their headshots
      all_assignments = @shows.flat_map(&:show_person_role_assignments)

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

      # Load cancelled vacancies (can't make it but still cast) for all shows
      @cancelled_vacancies_by_show = {}
      @shows.each do |show|
        @cancelled_vacancies_by_show[show.id] = show.cancelled_vacancies_by_assignment
      end

      # Load open vacancies for non-linked shows (person removed, role needs filling)
      @open_vacancies_by_show = {}
      @shows.each do |show|
        next if show.linked? # Linked shows keep person cast with "can't make it" indicator
        open_vacancies = show.role_vacancies.open.includes(:role, :vacated_by).to_a
        @open_vacancies_by_show[show.id] = open_vacancies.group_by(&:role_id)
      end

      # Load sign-up registrations for shows that have linked sign-up forms
      sign_up_registrations = SignUpRegistration
        .joins(sign_up_slot: :sign_up_form_instance)
        .where(sign_up_form_instances: { show_id: show_ids })
        .where(status: %w[confirmed waitlisted])
        .includes(:person, person: { profile_headshots: { image_attachment: :blob } }, sign_up_slot: { sign_up_form_instance: :sign_up_form })
        .to_a

      @sign_up_registrations_by_show = sign_up_registrations.group_by { |r| r.sign_up_slot.sign_up_form_instance.show_id }
    end

    def show_cast
      @availability = build_availability_hash(@show)

      # Use available_roles which respects show.use_custom_roles
      @roles = @show.available_roles.to_a
      @roles_count = @roles.sum { |r| r.quantity || 1 }  # Total slots, not role count

      # Get restricted roles for the filter dropdown
      @restricted_roles = @roles.select(&:restricted?)

      # Build eligible member data for restricted role filtering
      @eligible_by_role_id = {}
      @restricted_roles.each do |role|
        eligible_members = role.eligible_members.to_a
        @eligible_by_role_id[role.id] = eligible_members.map { |m| "#{m.class.name}_#{m.id}" }
      end

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
      @talent_pool = @production.effective_talent_pool

      @pool_people = @talent_pool.people
                     .includes(profile_headshots: { image_attachment: :blob })
                     .to_a

      @pool_groups = @talent_pool.groups
                     .includes(profile_headshots: { image_attachment: :blob })
                     .to_a

      @pool_members = @pool_people + @pool_groups

      # Build set of assigned member keys for quick lookup
      @assigned_member_keys = Set.new(@assignments.map { |a| "#{a.assignable_type}_#{a.assignable_id}" })

      # Load cancelled vacancies where person can't make it but is still cast
      @cancelled_vacancies_by_assignment = @show.cancelled_vacancies_by_assignment

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

      # Load sign-up registrations if this show has a linked sign-up form
      @sign_up_registrations = @show.sign_up_registrations.includes(person: { profile_headshots: { image_attachment: :blob } }).to_a

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

    # Search people in the organization for manual/hybrid casting
    # Returns JSON with matching people (and optionally groups)
    def search_people
      q = (params[:q] || params[:query]).to_s.strip

      if q.length < 2
        render json: { people: [], groups: [] }
        return
      end

      # Search for people in the organization (case-insensitive)
      people = Current.organization.people
                      .where("LOWER(name) LIKE LOWER(:q) OR LOWER(email) LIKE LOWER(:q)", q: "%#{q}%")
                      .order(:name)
                      .limit(20)
                      .includes(profile_headshots: { image_attachment: :blob })

      # Also search groups if include_groups param is present
      groups = []
      if params[:include_groups] == "true"
        groups = Current.organization.groups
                        .where("LOWER(name) LIKE LOWER(:q)", q: "%#{q}%")
                        .order(:name)
                        .limit(10)
                        .includes(profile_headshots: { image_attachment: :blob })
      end

      render json: {
        people: people.map { |p| person_search_result(p) },
        groups: groups.map { |g| group_search_result(g) }
      }
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

      # Validate eligibility for restricted roles (unless force is true - user confirmed in modal)
      if role.restricted? && !role.eligible?(assignable) && !params[:force]
        render json: { error: "This cast member is not eligible for this restricted role" }, status: :unprocessable_entity
        return
      end

      # Check if this assignable is already assigned to this role - silently ignore (no-op)
      existing_assignment = @show.show_person_role_assignments.find_by(assignable: assignable, role: role)
      if existing_assignment
        # Already assigned - just return success with current state (no-op)
        # This handles the case where user drags someone who's already in a multi-person role
        return render_assignment_success_response
      end

      # Check if role has available slots
      if role.fully_filled?(@show)
        render json: { error: "This role is already fully cast" }, status: :unprocessable_entity
        return
      end

      # Make the assignment (position is auto-assigned by model callback)
      # Use find_or_create_by to handle race conditions with unique constraint
      begin
        assignment = @show.show_person_role_assignments.create!(assignable: assignable, role: role)
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
        # Already assigned (race condition or validation) - just return success if it's the uniqueness error
        if e.is_a?(ActiveRecord::RecordNotUnique) || e.message.include?("already assigned")
          return render_assignment_success_response
        end
        raise e
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

      cast_members_locals = build_cast_members_list_locals(@show, @availability)
      cast_members_html = render_to_string(partial: "manage/casting/cast_members_list",
                                           locals: cast_members_locals)
      roles_html = render_to_string(partial: "manage/casting/roles_list", locals: { show: @show, sync_info: sync_info, click_to_add: click_to_add? })

      # Calculate progress using quantity-based slot counting
      progress = @show.casting_progress
      fully_cast = progress[:percentage] == 100

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
          assignment_count: progress[:filled],
          role_count: progress[:total],
          percentage: progress[:percentage]
        }
      }
    end

    def assign_guest_to_role
      # Get guest info
      guest_name = params[:guest_name].to_s.strip
      guest_email = params[:guest_email].to_s.strip.presence

      if guest_name.blank?
        render json: { error: "Guest name is required" }, status: :unprocessable_entity
        return
      end

      # Find the role
      role = Role.find(params[:role_id])

      # Check if role is restricted - guests cannot be assigned unless force is true
      if role.restricted? && !params[:force]
        render json: { error: "Guests cannot be assigned to restricted roles" }, status: :unprocessable_entity
        return
      end

      # Check if role has available slots
      if role.fully_filled?(@show)
        render json: { error: "This role is already fully cast" }, status: :unprocessable_entity
        return
      end

      # Check if there's an existing Person with this email - if so, use that person instead
      if guest_email.present?
        existing_person = Current.organization.people.find_by(email: guest_email)
        if existing_person
          # Found matching person - assign them instead of creating a guest
          existing_assignment = @show.show_person_role_assignments.find_by(assignable: existing_person, role: role)
          if existing_assignment
            render json: { error: "This person is already assigned to this role" }, status: :unprocessable_entity
            return
          end

          @show.show_person_role_assignments.create!(assignable: existing_person, role: role)
        else
          # Create guest assignment
          @show.show_person_role_assignments.create!(
            role: role,
            guest_name: guest_name,
            guest_email: guest_email
          )
        end
      else
        # Create guest assignment without email
        @show.show_person_role_assignments.create!(
          role: role,
          guest_name: guest_name,
          guest_email: nil
        )
      end

      # Generate the HTML to return
      @availability = build_availability_hash(@show)

      sync_info = nil
      linked_shows = []
      is_linked = @show.linked?
      if is_linked
        linked_shows = @show.linked_shows.to_a
        sync_info = build_linkage_sync_info(@show, linked_shows)
      end

      cast_members_locals = build_cast_members_list_locals(@show, @availability)
      cast_members_html = render_to_string(partial: "manage/casting/cast_members_list",
                                           locals: cast_members_locals)
      roles_html = render_to_string(partial: "manage/casting/roles_list", locals: { show: @show, sync_info: sync_info, click_to_add: click_to_add? })

      progress = @show.casting_progress
      fully_cast = progress[:percentage] == 100

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
          assignment_count: progress[:filled],
          role_count: progress[:total],
          percentage: progress[:percentage]
        }
      }
    end

    def remove_person_from_role
      # Support assignment_id, or role_id + position for removal
      removed_assignable_type = nil
      removed_assignable_id = nil

      if params[:assignment_id]
        assignment = @show.show_person_role_assignments.find(params[:assignment_id])
        if assignment
          removed_assignable_type = assignment.assignable_type
          removed_assignable_id = assignment.assignable_id
        end
        assignment&.destroy!
      elsif params[:role_id] && params[:position]
        # Remove specific slot by position (for multi-person roles)
        assignment = @show.show_person_role_assignments.find_by(role_id: params[:role_id], position: params[:position])
        if assignment
          removed_assignable_type = assignment.assignable_type
          removed_assignable_id = assignment.assignable_id
          assignment.destroy!
        end
      elsif params[:role_id]
        # Legacy: remove first assignment for this role (backward compatibility)
        assignment = @show.show_person_role_assignments.where(role_id: params[:role_id]).first
        if assignment
          removed_assignable_type = assignment.assignable_type
          removed_assignable_id = assignment.assignable_id
          assignment.destroy!
        end
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

      cast_members_locals = build_cast_members_list_locals(@show, @availability)
      cast_members_html = render_to_string(partial: "manage/casting/cast_members_list",
                                           locals: cast_members_locals)
      roles_html = render_to_string(partial: "manage/casting/roles_list", locals: { show: @show, sync_info: sync_info, click_to_add: click_to_add? })

      # Calculate progress using quantity-based slot counting
      progress = @show.casting_progress
      fully_cast = progress[:percentage] == 100

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
          assignment_count: progress[:filled],
          role_count: progress[:total],
          percentage: progress[:percentage]
        }
      }
    end

    # Replace an existing assignment with a new person/group
    # This removes the old assignment and creates a new one in a single transaction
    def replace_assignment
      assignment = @show.show_person_role_assignments.find(params[:assignment_id])
      role = assignment.role
      position = assignment.position

      # Get the new assignable
      if params[:new_person_id].present?
        new_assignable = Current.organization.people.find(params[:new_person_id])
      elsif params[:new_group_id].present?
        new_assignable = Current.organization.groups.find(params[:new_group_id])
      else
        render json: { error: "Must provide new_person_id or new_group_id" }, status: :unprocessable_entity
        return
      end

      # Check if the new assignable is already assigned to this role
      existing = @show.show_person_role_assignments.find_by(assignable: new_assignable, role: role)
      if existing && existing.id != assignment.id
        render json: { error: "#{new_assignable.name} is already assigned to this role" }, status: :unprocessable_entity
        return
      end

      # If moving from another role (source_role_id), also remove from there
      if params[:source_role_id].present? && params[:source_role_id].to_s != role.id.to_s
        source_assignment = @show.show_person_role_assignments.find_by(
          role_id: params[:source_role_id],
          assignable: new_assignable
        )
        source_assignment&.destroy!
      end

      # Do the replacement in a transaction
      ActiveRecord::Base.transaction do
        # Destroy old assignment
        assignment.destroy!

        # Create new assignment with the same position
        @show.show_person_role_assignments.create!(
          assignable: new_assignable,
          role: role,
          position: position
        )
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

      cast_members_locals = build_cast_members_list_locals(@show, @availability)
      cast_members_html = render_to_string(partial: "manage/casting/cast_members_list",
                                           locals: cast_members_locals)
      roles_html = render_to_string(partial: "manage/casting/roles_list", locals: { show: @show, sync_info: sync_info, click_to_add: click_to_add? })

      # Calculate progress using quantity-based slot counting
      progress = @show.casting_progress
      fully_cast = progress[:percentage] == 100

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
          assignment_count: progress[:filled],
          role_count: progress[:total],
          percentage: progress[:percentage]
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

      cast_members_locals = build_cast_members_list_locals(@show, @availability)
      cast_members_html = render_to_string(partial: "manage/casting/cast_members_list",
                                           locals: cast_members_locals)
      roles_html = render_to_string(partial: "manage/casting/roles_list", locals: { show: @show, sync_info: sync_info, click_to_add: click_to_add? })

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
        redirect_to manage_casting_show_cast_path(@production, @show),
                    alert: "Cannot finalize casting until all roles are filled."
        return
      end

      # For linked shows, gather all shows to finalize together
      shows_to_finalize = [ @show ]
      if @show.linked?
        linked_shows = @show.linked_shows.to_a
        sync_info = build_linkage_sync_info(@show, linked_shows)

        unless sync_info[:all_in_sync]
          redirect_to manage_casting_show_cast_path(@production, @show),
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

      # First pass to count recipients for batch creation
      shows_to_finalize.each do |show|
        # Get current cast members who need notification
        unnotified_assignments = show.unnotified_cast_members
        unnotified_assignments.each do |a|
          next unless a.role  # Skip orphaned assignments
          next if a.guest?    # Skip guest assignments (no person to notify)
          next unless a.assignable  # Skip if assignable was deleted

          # For groups, get all members; for people, just the person
          recipients = a.assignable.is_a?(Group) ? a.assignable.group_memberships.select(&:notifications_enabled?).map(&:person) : [ a.assignable ]

          recipients.each do |person|
            next unless person&.email.present?
            cast_notifications_by_person[person] ||= []
            cast_notifications_by_person[person] << { show: show, role: a.role, assignable: a.assignable }
          end
        end

        # Get removed cast members who need notification
        removed_members = show.removed_cast_members
        removed_members.each do |assignable|
          next unless assignable  # Skip nil assignables
          prev_notification = show.show_cast_notifications
                                  .cast_notifications
                                  .where(assignable: assignable)
                                  .order(notified_at: :desc)
                                  .first
          next unless prev_notification&.role

          recipients = assignable.is_a?(Group) ? assignable.group_memberships.select(&:notifications_enabled?).map(&:person) : [ assignable ]

          recipients.each do |person|
            next unless person&.email.present?
            removed_notifications_by_person[person] ||= []
            removed_notifications_by_person[person] << { show: show, role: prev_notification.role, assignable: assignable }
          end
        end
      end

      # Create email batch if sending to multiple recipients
      total_recipients = cast_notifications_by_person.size + removed_notifications_by_person.size
      email_batch = nil
      if total_recipients > 1
        email_batch = EmailBatch.create!(
          user: Current.user,
          subject: cast_subject,
          recipient_count: total_recipients,
          sent_at: Time.current
        )
      end

      # Send consolidated emails for cast members
      cast_notifications_by_person.each do |person, assignments|
        send_consolidated_cast_email(person, assignments, cast_body, cast_subject, :cast, email_batch_id: email_batch&.id)
      end

      # Send consolidated emails for removed members
      removed_notifications_by_person.each do |person, assignments|
        send_consolidated_cast_email(person, assignments, removed_body, removed_subject, :removed, email_batch_id: email_batch&.id)
      end

      # Finalize all shows and record notifications
      shows_to_finalize.each do |show|
        # Close any open vacancies
        show.role_vacancies.open.update_all(status: :filled, filled_at: Time.current)

        # Record notifications for current cast members
        show.unnotified_cast_members.each do |a|
          next unless a.role
          next if a.guest? # Guests don't have assignable records
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
        redirect_to manage_casting_show_cast_path(@production, @show),
                    notice: "Casting finalized for #{finalized_count} linked events and notifications sent!"
      else
        redirect_to manage_casting_show_cast_path(@production, @show),
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
        redirect_to manage_casting_show_cast_path(@production, @show),
                    notice: "Casting reopened for #{shows_to_reopen.count} linked events. You can now make changes."
      else
        redirect_to manage_casting_show_cast_path(@production, @show),
                    notice: "Casting reopened. You can now make changes."
      end
    end

    def copy_cast_to_linked
      unless @show.linked?
        redirect_to manage_casting_show_cast_path(@production, @show),
                    alert: "This event is not linked to any other events."
        return
      end

      linked_shows = @show.linked_shows.to_a
      if linked_shows.empty?
        redirect_to manage_casting_show_cast_path(@production, @show),
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

      redirect_to manage_casting_show_cast_path(@production, @show),
                  notice: "Roles and cast successfully synced to #{linked_shows.count} linked #{'event'.pluralize(linked_shows.count)}."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to manage_casting_show_cast_path(@production, @show),
                  alert: "Failed to sync: #{e.message}"
    end

    private

    # Render a success response for assignment operations (used for both new assignments and no-ops)
    def render_assignment_success_response
      @availability = build_availability_hash(@show)

      # Build linkage sync info for linked shows
      sync_info = nil
      linked_shows = []
      is_linked = @show.linked?
      if is_linked
        linked_shows = @show.linked_shows.to_a
        sync_info = build_linkage_sync_info(@show, linked_shows)
      end

      cast_members_locals = build_cast_members_list_locals(@show, @availability)
      cast_members_html = render_to_string(partial: "manage/casting/cast_members_list",
                                           locals: cast_members_locals)
      roles_html = render_to_string(partial: "manage/casting/roles_list", locals: { show: @show, sync_info: sync_info, click_to_add: click_to_add? })

      progress = @show.casting_progress
      fully_cast = progress[:percentage] == 100

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
          assignment_count: progress[:filled],
          role_count: progress[:total],
          percentage: progress[:percentage]
        }
      }
    end

    def person_search_result(person)
      {
        id: person.id,
        type: "Person",
        name: person.name,
        email: person.email,
        initials: person.initials,
        headshot_url: person.safe_headshot_variant(:thumb)&.then { |v| Rails.application.routes.url_helpers.url_for(v) rescue nil }
      }
    end

    def group_search_result(group)
      {
        id: group.id,
        type: "Group",
        name: group.name,
        initials: group.initials,
        headshot_url: group.safe_headshot_variant(:thumb)&.then { |v| Rails.application.routes.url_helpers.url_for(v) rescue nil }
      }
    end

    def check_not_third_party
      if @production.type_third_party?
        redirect_to manage_shows_path(@production), alert: "Casting is not available for third-party productions"
      end
    end

    # Helper to determine if click-to-add should be enabled for roles
    # Now always enabled - talent_pool includes this functionality (formerly hybrid-only)
    def click_to_add?
      true
    end

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
          # Update existing role to match source (including quantity and category)
          target_role.update!(
            position: source_role.position,
            quantity: source_role.quantity,
            category: source_role.category,
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
          # Create new role with all attributes from source
          eligibilities_to_copy = source_role.restricted? ? source_role.role_eligibilities.to_a : []
          should_be_restricted = source_role.restricted? && eligibilities_to_copy.any?

          new_role = target_show.custom_roles.new(
            name: source_role.name,
            position: source_role.position,
            quantity: source_role.quantity,
            category: source_role.category,
            restricted: should_be_restricted,
            production: target_show.production
          )

          # Set pending eligible member IDs to pass validation for restricted roles
          if should_be_restricted
            new_role.pending_eligible_member_ids = eligibilities_to_copy.map { |e| "#{e.member_type}_#{e.member_id}" }
          end

          new_role.save!

          # Copy eligibilities after save
          if should_be_restricted
            eligibilities_to_copy.each do |eligibility|
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
      unless Current.organization
        redirect_to select_organization_path, alert: "Please select an organization first."
        return
      end
      @production = Current.organization.productions.find(params.require(:production_id))
      sync_current_production(@production)
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

    # Build the locals hash for rendering cast_members_list partial
    # This ensures consistent data is passed across all assignment responses
    def build_cast_members_list_locals(show, availability)
      # Reload assignments to get fresh data
      assignments = show.show_person_role_assignments.reload

      # Build assigned member keys set
      assigned_member_keys = Set.new(assignments.map { |a| "#{a.assignable_type}_#{a.assignable_id}" })

      # Build linked show data
      linked_shows = []
      linked_availability = {}
      if show.linked?
        linked_shows = show.linked_shows.to_a
        linked_availability = build_linked_availability_hash(linked_shows)
      end

      # Get pool members with headshots
      talent_pool = show.production.effective_talent_pool
      pool_people = talent_pool.people
                               .includes(profile_headshots: { image_attachment: :blob })
                               .to_a
      pool_groups = talent_pool.groups
                               .includes(profile_headshots: { image_attachment: :blob })
                               .to_a
      pool_members = pool_people + pool_groups

      {
        show: show,
        availability: availability,
        pool_members: pool_members,
        assigned_member_keys: assigned_member_keys,
        linked_availability: linked_availability,
        linked_shows: linked_shows
      }
    end

    # Build a hash of availability across all linked shows
    # Returns { "Person_123" => { total: 3, available: 2, shows: [{ show_id: 1, available: true }, ...] } }
    def build_linked_availability_hash(linked_shows)
      return {} if linked_shows.empty?

      result = {}
      show_ids = linked_shows.map(&:id)

      # Build a lookup for show dates
      show_dates = linked_shows.index_by(&:id)

      # Load all availability records for linked shows
      ShowAvailability.where(show_id: show_ids).each do |avail|
        key = "#{avail.available_entity_type}_#{avail.available_entity_id}"
        result[key] ||= { total: linked_shows.count, available: 0, shows: [] }
        show = show_dates[avail.show_id]
        result[key][:shows] << {
          show_id: avail.show_id,
          available: avail.available?,
          date_and_time: show&.date_and_time
        }
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

    # Send a single consolidated email to a person with all their assignments across linked shows
    def send_consolidated_cast_email(person, assignments, email_body, subject, notification_type, email_batch_id: nil)
      # The email_body is the template with {{placeholders}} (from the preview editor).
      # Personalize it for this specific recipient by substituting their actual values.
      shows = assignments.map { |a| a[:show] }.uniq.sort_by(&:date_and_time)
      role_names = assignments.map { |a| a[:role].name }.uniq
      dates = shows.map { |s| s.date_and_time.strftime("%B %-d") }.uniq
      show_dates = dates.count > 2 ? "#{dates.first} - #{dates.last}" : dates.join(" & ")
      shows_list = shows.map { |s| "<li>#{s.date_and_time.strftime('%A, %B %-d at %-l:%M %p')}: #{s.display_name}</li>" }.join("\n")

      variables = {
        "production_name" => @production.name,
        "show_dates" => show_dates,
        "shows_list" => shows_list,
        "role_name" => role_names.join(", "),
        "role_names" => role_names.join(", ")
      }

      # Interpolate {{placeholders}} in the body and subject
      personalized_body = email_body.dup
      personalized_subject = subject.dup
      variables.each do |key, value|
        personalized_body.gsub!(/\{\{\s*#{Regexp.escape(key)}\s*\}\}/, value.to_s)
        personalized_subject.gsub!(/\{\{\s*#{Regexp.escape(key)}\s*\}\}/, value.to_s)
      end

      # Use the first show as the primary for the mailer (it needs a show reference)
      primary_show = assignments.first[:show]

      if notification_type == :cast
        CastingNotificationService.send_cast_notification(
          person: person,
          show: primary_show,
          production: @production,
          sender: Current.user,
          body: personalized_body,
          subject: personalized_subject,
          email_batch_id: email_batch_id
        )
      else
        CastingNotificationService.send_removed_notification(
          person: person,
          show: primary_show,
          production: @production,
          sender: Current.user,
          body: personalized_body,
          subject: personalized_subject,
          email_batch_id: email_batch_id
        )
      end
    end

    def default_cast_email_subject
      template = ContentTemplate.active.find_by(key: "cast_notification")
      template&.subject || "Cast Confirmation"
    end

    def default_cast_email_body
      template = ContentTemplate.active.find_by(key: "cast_notification")
      template&.body || ""
    end

    def default_removed_email_subject
      variables = build_casting_email_variables
      ContentTemplateService.render_subject("removed_from_cast_notification", variables)
    end

    def default_removed_email_body
      template = ContentTemplate.active.find_by(key: "removed_from_cast_notification")
      template&.body || ""
    end

    # Build variables for casting email templates
    def build_casting_email_variables
      all_shows = if @show.linked? && @linked_shows.present? && @linked_shows.any?
                    [ @show ] + @linked_shows
      else
                    [ @show ]
      end

      sorted_shows = all_shows.sort_by(&:date_and_time)
      dates = sorted_shows.map { |s| s.date_and_time.strftime("%B %-d") }.uniq

      show_dates = if dates.count > 2
                     "#{dates.first} - #{dates.last}"
      else
                     dates.join(" & ")
      end

      shows_list = sorted_shows.map do |s|
        show_name = s.display_name
        date = s.date_and_time.strftime("%A, %B %-d at %-l:%M %p")
        "<li>#{date}: #{show_name}</li>"
      end.join("\n")

      # Get all unique role names from the show(s)
      all_roles = all_shows.flat_map { |s| s.show_person_role_assignments.includes(:role).map(&:role) }.uniq
      role_names = all_roles.map(&:name).uniq
      role_name = role_names.first || "Cast Member"
      role_names_list = role_names.join(", ")

      {
        production_name: @production.name,
        show_dates: show_dates,
        shows_list: shows_list,
        role_name: role_name,
        role_names: role_names_list
      }
    end

    # Build sync info comparing this show's cast with linked shows
    def build_linkage_sync_info(show, linked_shows)
      current_roles = show.available_roles.pluck(:id, :name).to_h
      # Build role signature including name, quantity, category, and restricted status for comparison
      current_role_signatures = show.available_roles.pluck(:name, :quantity, :category, :restricted).map { |r| r.join("|") }.sort

      sync_info = {
        all_in_sync: true,
        roles_match: true,
        casts_match: true,
        linked_shows_info: [],
        current_role_names: current_roles.values.sort
      }

      linked_shows.each do |linked_show|
        linked_roles = linked_show.available_roles.pluck(:id, :name).to_h
        linked_role_signatures = linked_show.available_roles.pluck(:name, :quantity, :category, :restricted).map { |r| r.join("|") }.sort

        # Check if roles match (by name, quantity, category, and restricted status)
        roles_match = current_role_signatures == linked_role_signatures

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
