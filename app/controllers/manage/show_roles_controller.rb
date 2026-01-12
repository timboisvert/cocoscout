# frozen_string_literal: true

module Manage
  class ShowRolesController < Manage::ManageController
    before_action :set_production
    before_action :set_show
    before_action :check_production_access
    before_action :ensure_user_is_manager
    before_action :set_role, only: %i[update destroy]

    # GET /manage/productions/:production_id/shows/:show_id/show_roles
    def index
      @roles = @show.custom_roles

      respond_to do |format|
        format.html { redirect_to edit_manage_production_show_path(@production, @show) }
        format.json { render json: roles_json(@roles) }
      end
    end

    # POST /manage/productions/:production_id/shows/:show_id/show_roles
    def create
      @role = @show.custom_roles.new(role_params)
      @role.production = @production

      # Set position to be at the end of the list
      max_position = @show.custom_roles.maximum(:position) || -1
      @role.position = max_position + 1

      ActiveRecord::Base.transaction do
        if @role.save
          update_eligible_members(@role)
          render json: { success: true, role: role_json(@role) }
        else
          render json: { success: false, errors: @role.errors.full_messages }, status: :unprocessable_entity
        end
      end
    rescue ActiveRecord::RecordInvalid => e
      render json: { success: false, errors: [ e.message ] }, status: :unprocessable_entity
    rescue => e
      Rails.logger.error "Error creating role: #{e.message}\n#{e.backtrace.first(10).join("\n")}"
      render json: { success: false, errors: [ "An unexpected error occurred" ] }, status: :internal_server_error
    end

    # PATCH /manage/productions/:production_id/shows/:show_id/show_roles/:id
    def update
      ActiveRecord::Base.transaction do
        if @role.update(role_params)
          update_eligible_members(@role)
          render json: { success: true, role: role_json(@role) }
        else
          render json: { success: false, errors: @role.errors.full_messages }, status: :unprocessable_entity
        end
      end
    rescue ActiveRecord::RecordInvalid => e
      render json: { success: false, errors: [ e.message ] }, status: :unprocessable_entity
    rescue => e
      Rails.logger.error "Error updating role: #{e.message}\n#{e.backtrace.first(10).join("\n")}"
      render json: { success: false, errors: [ "An unexpected error occurred" ] }, status: :internal_server_error
    end

    # DELETE /manage/productions/:production_id/shows/:show_id/show_roles/:id
    def destroy
      assignments_count = @role.show_person_role_assignments.count

      if params[:confirm_delete] == "true" || assignments_count == 0
        @role.destroy!
        render json: { success: true }
      else
        render json: {
          success: false,
          needs_confirmation: true,
          assignments_count: assignments_count,
          message: "This role has #{assignments_count} #{'assignment'.pluralize(assignments_count)}. Are you sure you want to delete it?"
        }, status: :unprocessable_entity
      end
    end

    # POST /manage/productions/:production_id/shows/:show_id/show_roles/reorder
    def reorder
      role_ids = params[:role_ids]
      role_ids.each_with_index do |id, index|
        @show.custom_roles.find(id).update(position: index)
      end
      head :ok
    end

    # POST /manage/productions/:production_id/shows/:show_id/show_roles/copy_from_production
    def copy_from_production
      if @show.custom_roles.any?
        render json: {
          success: false,
          message: "This event already has custom roles. Delete them first to copy from production."
        }, status: :unprocessable_entity
        return
      end

      @show.copy_roles_from_production!
      @show.update!(use_custom_roles: true)

      render json: {
        success: true,
        roles: roles_json(@show.custom_roles.reload)
      }
    end

    # GET /manage/productions/:production_id/shows/:show_id/show_roles/talent_pool_members
    def talent_pool_members
      talent_pool = @production.talent_pool

      people = talent_pool.people.includes(profile_headshots: { image_attachment: :blob })

      groups = talent_pool.groups.includes(profile_headshots: { image_attachment: :blob })

      members = (people.to_a + groups.to_a).sort_by(&:name)

      render json: members.map { |m|
        {
          id: m.id,
          type: m.class.name,
          key: "#{m.class.name}_#{m.id}",
          name: m.name,
          initials: m.initials,
          headshot_url: m.safe_headshot_variant(:thumb) ? url_for(m.safe_headshot_variant(:thumb)) : nil
        }
      }
    end

    # GET /manage/productions/:production_id/shows/:show_id/show_roles/check_assignments
    # Returns current assignments that would be deleted when toggling custom roles
    def check_assignments
      assignments = @show.show_person_role_assignments.includes(:role)

      # Preload assignables
      person_ids = assignments.select { |a| a.assignable_type == "Person" }.map(&:assignable_id)
      group_ids = assignments.select { |a| a.assignable_type == "Group" }.map(&:assignable_id)

      people_by_id = Person.where(id: person_ids)
                           .includes(profile_headshots: { image_attachment: :blob })
                           .index_by(&:id)
      groups_by_id = Group.where(id: group_ids)
                          .includes(profile_headshots: { image_attachment: :blob })
                          .index_by(&:id)

      assignments_data = assignments.map do |a|
        assignable = a.assignable_type == "Person" ? people_by_id[a.assignable_id] : groups_by_id[a.assignable_id]
        {
          id: a.id,
          role_name: a.role&.name || "Unknown Role",
          assignable_name: assignable&.name || "Unknown",
          assignable_type: a.assignable_type,
          headshot_url: assignable&.safe_headshot_variant(:thumb) ? url_for(assignable.safe_headshot_variant(:thumb)) : nil,
          initials: assignable&.initials || "?"
        }
      end

      # Get linked shows if this show is linked
      linked_shows_data = if @show.linked?
        @show.event_linkage.shows.where.not(id: @show.id).order(:date_and_time).map do |show|
          {
            id: show.id,
            title: show.title,
            event_date: show.date_and_time&.strftime("%B %-d, %Y")
          }
        end
      else
        []
      end

      render json: {
        has_assignments: assignments.any?,
        count: assignments.count,
        assignments: assignments_data,
        currently_using_custom_roles: @show.use_custom_roles?,
        switching_to: params[:switching_to] || (@show.use_custom_roles? ? "production" : "custom"),
        is_linked: @show.linked?,
        linked_shows: linked_shows_data
      }
    end

    # POST /manage/productions/:production_id/shows/:show_id/show_roles/clear_assignments
    # Deletes all assignments for this show (called when confirming toggle)
    def clear_assignments
      @show.show_person_role_assignments.destroy_all
      render json: { success: true }
    end

    private

    def set_production
      unless Current.organization
        redirect_to select_organization_path, alert: "Please select an organization first."
        return
      end
      @production = Current.organization.productions.find(params.expect(:production_id))
      sync_current_production(@production)
    end

    def set_show
      @show = @production.shows.find(params.expect(:show_id))
    end

    def set_role
      @role = @show.custom_roles.find(params.expect(:id))
    end

    def role_params
      params.expect(show_role: [ :name, :restricted, :quantity, :category ])
    end

    def update_eligible_members(role)
      eligible_member_ids = params.dig(:show_role, :eligible_member_ids)&.reject(&:blank?) || []

      if role.restricted? && eligible_member_ids.any?
        new_members = eligible_member_ids.map do |member_key|
          type, id = member_key.split("_", 2)
          { member_type: type, member_id: id.to_i }
        end

        # Remove eligibilities that are no longer selected
        role.role_eligibilities.each do |eligibility|
          member_key = { member_type: eligibility.member_type, member_id: eligibility.member_id }
          eligibility.destroy unless new_members.include?(member_key)
        end

        # Add new eligibilities
        existing_keys = role.role_eligibilities.reload.map { |e| { member_type: e.member_type, member_id: e.member_id } }
        new_members.each do |member|
          unless existing_keys.include?(member)
            role.role_eligibilities.create!(member_type: member[:member_type], member_id: member[:member_id])
          end
        end
      else
        role.role_eligibilities.destroy_all
      end
    end

    def role_json(role)
      {
        id: role.id,
        name: role.name,
        position: role.position,
        restricted: role.restricted?,
        quantity: role.quantity,
        category: role.category,
        eligible_member_keys: role.role_eligibilities.map { |e| "#{e.member_type}_#{e.member_id}" },
        eligible_members: role.eligible_members.map { |m|
          {
            id: m.id,
            type: m.class.name,
            name: m.name,
            initials: m.initials,
            headshot_url: m.safe_headshot_variant(:thumb) ? url_for(m.safe_headshot_variant(:thumb)) : nil
          }
        },
        assignments_count: role.show_person_role_assignments.count
      }
    end

    def roles_json(roles)
      roles.map { |role| role_json(role) }
    end
  end
end
