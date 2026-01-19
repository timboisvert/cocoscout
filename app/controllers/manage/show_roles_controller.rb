# frozen_string_literal: true

module Manage
  class ShowRolesController < Manage::ManageController
    before_action :set_production
    before_action :set_show
    before_action :check_production_access
    before_action :ensure_user_is_manager
    before_action :set_role, only: %i[update destroy slot_change_preview execute_slot_change]

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

      # Set pending eligible members for validation
      @role.pending_eligible_member_ids = params.dig(:show_role, :eligible_member_ids)

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
      # Set pending eligible members for validation
      @role.pending_eligible_member_ids = params.dig(:show_role, :eligible_member_ids)

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
      talent_pool = @production.effective_talent_pool

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
    # Also updates use_custom_roles based on switching_to parameter
    def clear_assignments
      @show.show_person_role_assignments.destroy_all

      # Update use_custom_roles based on switching_to parameter
      switching_to = params[:switching_to]
      if switching_to == "custom"
        @show.update!(use_custom_roles: true)
      elsif switching_to == "production"
        @show.update!(use_custom_roles: false)
      end

      render json: { success: true, use_custom_roles: @show.use_custom_roles? }
    end

    # GET /manage/productions/:production_id/shows/:show_id/show_roles/migration_preview
    # Returns a preview of how assignments would map when switching between custom/production roles
    def migration_preview
      switching_to = params[:switching_to] || (@show.use_custom_roles? ? "production" : "custom")

      # Get current assignments with their roles
      current_assignments = @show.show_person_role_assignments.includes(:role)

      # Preload assignables for display
      person_ids = current_assignments.select { |a| a.assignable_type == "Person" }.map(&:assignable_id)
      group_ids = current_assignments.select { |a| a.assignable_type == "Group" }.map(&:assignable_id)

      people_by_id = Person.where(id: person_ids)
                           .includes(profile_headshots: { image_attachment: :blob })
                           .index_by(&:id)
      groups_by_id = Group.where(id: group_ids)
                          .includes(profile_headshots: { image_attachment: :blob })
                          .index_by(&:id)

      # Determine source and target roles
      if switching_to == "custom"
        # Switching to custom roles - target roles will be copies of production roles
        source_roles = @production.roles.production_roles.order(:position)
        # If custom roles already exist, use those; otherwise will create from production
        target_roles = @show.custom_roles.any? ? @show.custom_roles.order(:position) : source_roles
        will_copy_roles = @show.custom_roles.empty?
      else
        # Switching to production roles
        source_roles = @show.custom_roles.order(:position)
        target_roles = @production.roles.production_roles.order(:position)
        will_copy_roles = false
      end

      # Build role name lookup for target roles
      target_roles_by_name = target_roles.index_by { |r| r.name.downcase.strip }

      # Build migration mappings
      mappings = current_assignments.map do |assignment|
        assignable = assignment.assignable_type == "Person" ? people_by_id[assignment.assignable_id] : groups_by_id[assignment.assignable_id]
        current_role = assignment.role

        # Find matching target role by name (case-insensitive)
        matched_role = current_role ? target_roles_by_name[current_role.name.downcase.strip] : nil

        {
          assignment_id: assignment.id,
          current_role_id: current_role&.id,
          current_role_name: current_role&.name || "Unknown Role",
          suggested_target_role_id: matched_role&.id,
          suggested_target_role_name: matched_role&.name,
          can_auto_map: matched_role.present?,
          assignable_id: assignment.assignable_id,
          assignable_type: assignment.assignable_type,
          assignable_name: assignable&.name || "Unknown",
          headshot_url: assignable&.safe_headshot_variant(:thumb) ? url_for(assignable.safe_headshot_variant(:thumb)) : nil,
          initials: assignable&.initials || "?",
          position: assignment.position
        }
      end

      # Group by whether they can be auto-mapped
      auto_mappable = mappings.select { |m| m[:can_auto_map] }
      needs_decision = mappings.reject { |m| m[:can_auto_map] }

      # Build target roles list for dropdown selection
      target_roles_list = target_roles.map do |role|
        {
          id: role.id,
          name: role.name,
          category: role.category,
          quantity: role.quantity
        }
      end

      # Get linked shows info if applicable
      linked_shows_data = if @show.linked?
        @show.event_linkage.shows.where.not(id: @show.id).order(:date_and_time).map do |show|
          {
            id: show.id,
            title: show.name_with_date,
            event_date: show.date_and_time&.strftime("%B %-d, %Y"),
            assignments_count: show.show_person_role_assignments.count
          }
        end
      else
        []
      end

      render json: {
        switching_to: switching_to,
        currently_using_custom_roles: @show.use_custom_roles?,
        will_copy_roles: will_copy_roles,
        total_assignments: current_assignments.count,
        auto_mappable_count: auto_mappable.count,
        needs_decision_count: needs_decision.count,
        mappings: mappings,
        target_roles: target_roles_list,
        is_linked: @show.linked?,
        linked_shows: linked_shows_data
      }
    end

    # POST /manage/productions/:production_id/shows/:show_id/show_roles/execute_migration
    # Executes the role migration with the specified mappings
    def execute_migration
      switching_to = params[:switching_to]
      role_mappings = params[:role_mappings] || [] # Array of {assignment_id, target_role_id, action}
      notify_changes = params[:notify_changes] != false

      unless %w[custom production].include?(switching_to)
        render json: { success: false, error: "Invalid switching_to value" }, status: :unprocessable_entity
        return
      end

      ActiveRecord::Base.transaction do
        # Track who is being added/removed for notifications
        people_removed = [] # Will be notified of removal
        people_kept = [] # Won't be notified (just transferred)

        # Skip the automatic assignment clearing callback - we're handling it manually
        @show.skip_assignment_clear_on_role_toggle = true

        # If switching to custom and no custom roles exist, copy from production first
        if switching_to == "custom" && @show.custom_roles.empty?
          @show.copy_roles_from_production!
        end

        # Determine target roles (reload to get freshly created custom roles)
        target_roles = switching_to == "custom" ? @show.custom_roles.reload : @production.roles.production_roles
        target_roles_by_id = target_roles.index_by(&:id)
        target_roles_by_name = target_roles.index_by { |r| r.name.downcase.strip }

        # Get current assignments
        current_assignments = @show.show_person_role_assignments.includes(:role).index_by(&:id)

        # Build a mapping index from provided params
        mappings_by_assignment_id = role_mappings.index_by { |m| m[:assignment_id].to_i }

        # Process each current assignment
        current_assignments.each do |assignment_id, assignment|
          mapping = mappings_by_assignment_id[assignment_id]

          if mapping
            action = mapping[:action] || "transfer"
            target_role_id = mapping[:target_role_id]&.to_i

            if action == "remove"
              # User explicitly chose to remove this assignment
              record_removal_for_notification(assignment, people_removed)
              assignment.destroy!
            elsif action == "transfer" && target_role_id.present?
              # Transfer to specified target role
              target_role = target_roles_by_id[target_role_id]
              if target_role
                # Check if role name changed
                if assignment.role&.name&.downcase&.strip == target_role.name.downcase.strip
                  # Same role name - just update the role_id, no notification needed
                  assignment.update!(role_id: target_role.id)
                  people_kept << { assignment: assignment, role: target_role }
                else
                  # Different role - this is a change, might want to notify
                  assignment.update!(role_id: target_role.id)
                  people_kept << { assignment: assignment, role: target_role }
                end
              else
                # Target role not found - remove assignment
                record_removal_for_notification(assignment, people_removed)
                assignment.destroy!
              end
            else
              # No mapping provided - try auto-mapping by role name
              matched_role = assignment.role ? target_roles_by_name[assignment.role.name.downcase.strip] : nil
              if matched_role
                assignment.update!(role_id: matched_role.id)
                people_kept << { assignment: assignment, role: matched_role }
              else
                # No match found - remove assignment
                record_removal_for_notification(assignment, people_removed)
                assignment.destroy!
              end
            end
          else
            # No mapping provided - try auto-mapping by role name
            matched_role = assignment.role ? target_roles_by_name[assignment.role.name.downcase.strip] : nil
            if matched_role
              assignment.update!(role_id: matched_role.id)
              people_kept << { assignment: assignment, role: matched_role }
            else
              # No match found - remove assignment
              record_removal_for_notification(assignment, people_removed)
              assignment.destroy!
            end
          end
        end

        # Update the use_custom_roles flag
        @show.update!(use_custom_roles: switching_to == "custom")

        # Delete custom roles if switching to production roles
        if switching_to == "production"
          @show.custom_roles.destroy_all
        end

        # Clear finalized status since cast has changed
        @show.update!(casting_finalized_at: nil) if @show.casting_finalized?

        # Handle linked shows if applicable
        if @show.linked? && params[:apply_to_linked] == true
          @show.event_linkage.shows.where.not(id: @show.id).each do |linked_show|
            migrate_linked_show(linked_show, switching_to, target_roles_by_name)
          end
        end

        render json: {
          success: true,
          use_custom_roles: @show.use_custom_roles?,
          removed_count: people_removed.uniq { |p| "#{p[:assignable_type]}_#{p[:assignable_id]}" }.count,
          kept_count: people_kept.count,
          message: build_migration_result_message(people_removed, people_kept)
        }
      end
    rescue ActiveRecord::RecordInvalid => e
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    rescue => e
      Rails.logger.error "Error executing role migration: #{e.message}\n#{e.backtrace.first(10).join("\n")}"
      render json: { success: false, error: "An unexpected error occurred" }, status: :internal_server_error
    end

    # POST /manage/productions/:production_id/shows/:show_id/show_roles/toggle_custom_roles
    # Toggles use_custom_roles flag on the show (called when there are no assignments to clear)
    def toggle_custom_roles
      enable = params[:enable] == true || params[:enable] == "true"
      @show.update!(use_custom_roles: enable)

      render json: { success: true, use_custom_roles: @show.use_custom_roles? }
    end

    # GET /manage/productions/:production_id/shows/:show_id/show_roles/:id/slot_change_preview
    # Returns a preview of how assignments would be affected by changing the role quantity
    def slot_change_preview
      new_quantity = params[:new_quantity].to_i
      current_quantity = @role.quantity

      # Get current assignments for this role
      assignments = @role.show_person_role_assignments.order(:position)

      # Preload assignables
      person_ids = assignments.select { |a| a.assignable_type == "Person" }.map(&:assignable_id)
      group_ids = assignments.select { |a| a.assignable_type == "Group" }.map(&:assignable_id)

      people_by_id = Person.where(id: person_ids)
                           .includes(profile_headshots: { image_attachment: :blob })
                           .index_by(&:id)
      groups_by_id = Group.where(id: group_ids)
                          .includes(profile_headshots: { image_attachment: :blob })
                          .index_by(&:id)

      # Build assignments data
      assignments_data = assignments.map.with_index do |a, index|
        assignable = a.assignable_type == "Person" ? people_by_id[a.assignable_id] : groups_by_id[a.assignable_id]
        {
          assignment_id: a.id,
          assignable_id: a.assignable_id,
          assignable_type: a.assignable_type,
          assignable_name: assignable&.name || "Unknown",
          headshot_url: assignable&.safe_headshot_variant(:thumb) ? url_for(assignable.safe_headshot_variant(:thumb)) : nil,
          initials: assignable&.initials || "?",
          position: index
        }
      end

      # Determine what action is needed
      current_count = assignments.count
      slots_being_removed = new_quantity < current_count ? current_count - new_quantity : 0
      slots_being_added = new_quantity > current_quantity ? new_quantity - current_quantity : 0

      render json: {
        role_id: @role.id,
        role_name: @role.name,
        current_quantity: current_quantity,
        new_quantity: new_quantity,
        current_assignment_count: current_count,
        slots_being_removed: slots_being_removed,
        slots_being_added: slots_being_added,
        needs_decision: slots_being_removed > 0,
        assignments: assignments_data
      }
    end

    # POST /manage/productions/:production_id/shows/:show_id/show_roles/:id/execute_slot_change
    # Executes the slot quantity change with specified assignment removals
    def execute_slot_change
      new_quantity = params[:new_quantity].to_i
      keep_assignment_ids = (params[:keep_assignment_ids] || []).map(&:to_i)

      if new_quantity < 1
        render json: { success: false, error: "Quantity must be at least 1" }, status: :unprocessable_entity
        return
      end

      ActiveRecord::Base.transaction do
        current_assignments = @role.show_person_role_assignments.order(:position)
        current_count = current_assignments.count

        # If reducing slots and we have more assignments than new quantity
        if new_quantity < current_count
          # Determine which assignments to remove
          if keep_assignment_ids.any?
            # User specified which to keep
            assignments_to_remove = current_assignments.where.not(id: keep_assignment_ids)
          else
            # No specific selection - remove from the end
            assignments_to_remove = current_assignments.offset(new_quantity)
          end

          assignments_to_remove.destroy_all

          # Re-index positions of remaining assignments to be contiguous
          @role.show_person_role_assignments.order(:position).each_with_index do |assignment, index|
            assignment.update_column(:position, index) if assignment.position != index
          end
        end

        # Update the role quantity
        @role.update!(quantity: new_quantity)

        # Return the updated role data
        render json: {
          success: true,
          role: role_json(@role.reload),
          message: new_quantity < current_count ?
            "Updated to #{new_quantity} #{'slot'.pluralize(new_quantity)}, #{current_count - new_quantity} #{'assignment'.pluralize(current_count - new_quantity)} removed." :
            "Updated to #{new_quantity} #{'slot'.pluralize(new_quantity)}."
        }
      end
    rescue ActiveRecord::RecordInvalid => e
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    rescue => e
      Rails.logger.error "Error executing slot change: #{e.message}\n#{e.backtrace.first(10).join("\n")}"
      render json: { success: false, error: "An unexpected error occurred" }, status: :internal_server_error
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

    # Record assignment removal for potential notification
    def record_removal_for_notification(assignment, people_removed)
      people_removed << {
        assignable_type: assignment.assignable_type,
        assignable_id: assignment.assignable_id,
        role_name: assignment.role&.name
      }
    end

    # Migrate a linked show to match the primary show's role mode
    def migrate_linked_show(linked_show, switching_to, target_roles_by_name)
      linked_show.show_person_role_assignments.includes(:role).each do |assignment|
        matched_role = assignment.role ? target_roles_by_name[assignment.role.name.downcase.strip] : nil
        if matched_role
          assignment.update!(role_id: matched_role.id)
        else
          assignment.destroy!
        end
      end

      linked_show.update!(use_custom_roles: switching_to == "custom")

      if switching_to == "production"
        linked_show.custom_roles.destroy_all
      elsif switching_to == "custom" && linked_show.custom_roles.empty?
        linked_show.copy_roles_from_production!
      end

      linked_show.update!(casting_finalized_at: nil) if linked_show.casting_finalized?
    end

    # Build a human-readable message about the migration result
    def build_migration_result_message(people_removed, people_kept)
      removed_count = people_removed.uniq { |p| "#{p[:assignable_type]}_#{p[:assignable_id]}" }.count
      kept_count = people_kept.count

      if removed_count == 0 && kept_count > 0
        "All #{kept_count} #{'assignment'.pluralize(kept_count)} transferred successfully."
      elsif removed_count > 0 && kept_count > 0
        "#{kept_count} #{'assignment'.pluralize(kept_count)} transferred, #{removed_count} removed."
      elsif removed_count > 0 && kept_count == 0
        "#{removed_count} #{'assignment'.pluralize(removed_count)} removed."
      else
        "Role mode switched successfully."
      end
    end
  end
end
