# frozen_string_literal: true

module Manage
  class CastingTablesController < Manage::ManageController
    before_action :ensure_user_is_manager, except: [ :index, :show ]
    before_action :set_casting_table, only: [ :show, :edit, :update, :assign, :unassign, :summary, :finalize ]

    def index
      @casting_tables = Current.organization.casting_tables
                                .includes(:productions, :shows, :created_by)
                                .order(created_at: :desc)

      @draft_tables = @casting_tables.draft
      @finalized_tables = @casting_tables.finalized
    end

    def show
      # Main casting grid view
      @shows = @casting_table.shows.order(:date_and_time)
      @productions = @casting_table.productions

      # Get members (people and groups)
      person_ids = @casting_table.casting_table_members.where(memberable_type: "Person").pluck(:memberable_id)
      group_ids = @casting_table.casting_table_members.where(memberable_type: "Group").pluck(:memberable_id)

      @people = Person.where(id: person_ids)
                      .includes(profile_headshots: { image_attachment: :blob })
                      .order(:name)
      @groups = Group.where(id: group_ids)
                     .includes(profile_headshots: { image_attachment: :blob })
                     .order(:name)

      @members = @people.to_a + @groups.to_a

      # Load availability data
      @availability = load_availability_data

      # Load draft assignments
      @draft_assignments = @casting_table.casting_table_draft_assignments
                                          .includes(:role, :assignable)
                                          .group_by { |da| [ da.show_id, da.assignable_type, da.assignable_id ] }

      # Load existing (finalized) assignments
      @existing_assignments = ShowPersonRoleAssignment.where(show_id: @shows.pluck(:id))
                                                       .includes(:role, :assignable)
                                                       .group_by { |a| [ a.show_id, a.assignable_type, a.assignable_id ] }

      # Load roles by show (using show.available_roles which handles custom roles)
      @roles_by_show = {}
      @shows.each do |show|
        @roles_by_show[show.id] = show.available_roles.order(:position).to_a
      end

      # Count assignments per member and per show
      @assignment_counts = count_assignments_per_member
      @show_assignment_counts = count_show_assignments

      # Count assignments per role per show (for capacity checking)
      @role_counts_by_show = count_role_assignments_by_show

      # Calculate total slots per show (sum of all role quantities)
      @show_total_slots = {}
      @shows.each do |show|
        roles = @roles_by_show[show.id] || []
        @show_total_slots[show.id] = roles.sum(&:quantity)
      end
    end

    def edit
      redirect_to manage_casting_table_path(@casting_table) unless @casting_table.draft?
    end

    def update
      if @casting_table.update(casting_table_params)
        redirect_to manage_casting_table_path(@casting_table), notice: "Casting table updated"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # AJAX: Add a draft assignment
    def assign
      unless @casting_table.draft?
        render json: { error: "Cannot modify finalized casting table" }, status: :unprocessable_entity
        return
      end

      show = @casting_table.shows.find_by(id: params[:show_id])
      role = Role.find_by(id: params[:role_id])

      unless show && role
        render json: { error: "Invalid show or role" }, status: :unprocessable_entity
        return
      end

      # Verify role belongs to the show's production
      unless role.production_id == show.production_id
        render json: { error: "Role does not belong to this production" }, status: :unprocessable_entity
        return
      end

      assignable_type = params[:assignable_type]
      assignable_id = params[:assignable_id].to_i

      # Verify the member is in this casting table
      unless @casting_table.casting_table_members.exists?(memberable_type: assignable_type, memberable_id: assignable_id)
        render json: { error: "Member not in casting table" }, status: :unprocessable_entity
        return
      end

      # Check role capacity
      existing_draft_count = @casting_table.casting_table_draft_assignments
                                           .where(show_id: show.id, role_id: role.id)
                                           .count
      existing_finalized_count = ShowPersonRoleAssignment.where(show_id: show.id, role_id: role.id).count
      total = existing_draft_count + existing_finalized_count

      if total >= role.quantity
        render json: { error: "This role is already at capacity (#{role.quantity} allowed)" }, status: :unprocessable_entity
        return
      end

      # Create or find draft assignment
      draft = @casting_table.casting_table_draft_assignments.find_or_create_by!(
        show_id: show.id,
        role_id: role.id,
        assignable_type: assignable_type,
        assignable_id: assignable_id
      )

      render json: {
        success: true,
        draft_id: draft.id,
        show_id: show.id,
        role_name: role.name,
        assignable_type: assignable_type,
        assignable_id: assignable_id
      }

    rescue ActiveRecord::RecordNotUnique
      render json: { error: "Already assigned" }, status: :unprocessable_entity
    end

    # AJAX: Remove a draft assignment
    def unassign
      unless @casting_table.draft?
        render json: { error: "Cannot modify finalized casting table" }, status: :unprocessable_entity
        return
      end

      draft = @casting_table.casting_table_draft_assignments.find_by(
        show_id: params[:show_id],
        assignable_type: params[:assignable_type],
        assignable_id: params[:assignable_id]
      )

      if draft
        role_id = draft.role_id
        role_name = draft.role.name
        draft.destroy
        render json: { success: true, role_id: role_id, role_name: role_name }
      else
        render json: { error: "Assignment not found" }, status: :not_found
      end
    end

    # Summary/confirmation before finalization
    def summary
      @shows = @casting_table.shows.order(:date_and_time).includes(:production)
      @draft_assignments = @casting_table.casting_table_draft_assignments
                                          .includes(:show, :role)
                                          .order("shows.date_and_time")

      # Group by show
      @assignments_by_show = @draft_assignments.group_by(&:show)

      # Get unique people who will be notified
      person_ids = @draft_assignments.where(assignable_type: "Person").pluck(:assignable_id).uniq
      group_ids = @draft_assignments.where(assignable_type: "Group").pluck(:assignable_id).uniq

      @people_to_notify = Person.where(id: person_ids).includes(:user).order(:name)
      @groups_to_notify = Group.where(id: group_ids).order(:name)
    end

    def finalize
      unless @casting_table.draft?
        redirect_to manage_casting_table_path(@casting_table), alert: "Already finalized"
        return
      end

      if @casting_table.casting_table_draft_assignments.empty?
        redirect_to manage_casting_table_path(@casting_table), alert: "No assignments to finalize"
        return
      end

      notify = params[:notify] == "1"

      if @casting_table.finalize!
        if notify
          # Queue notification emails and record that we sent them
          send_casting_notifications
          @casting_table.record_notifications!
          redirect_to manage_casting_table_path(@casting_table), notice: "Casting finalized and notifications sent!"
        else
          redirect_to manage_casting_table_path(@casting_table), notice: "Casting finalized successfully!"
        end
      else
        redirect_to manage_casting_table_summary_path(@casting_table), alert: "Error finalizing casting table"
      end
    end

    private

    def set_casting_table
      @casting_table = Current.organization.casting_tables.find(params[:id])
    end

    def casting_table_params
      params.require(:casting_table).permit(:name)
    end

    def load_availability_data
      show_ids = @casting_table.shows.pluck(:id)
      person_ids = @casting_table.casting_table_members.where(memberable_type: "Person").pluck(:memberable_id)
      group_ids = @casting_table.casting_table_members.where(memberable_type: "Group").pluck(:memberable_id)

      # ShowAvailability: polymorphic available_entity (Person/Group), show_id, status (enum)
      availabilities = ShowAvailability.where(show_id: show_ids)
                                        .where(
                                          "(available_entity_type = 'Person' AND available_entity_id IN (?)) OR (available_entity_type = 'Group' AND available_entity_id IN (?))",
                                          person_ids, group_ids
                                        )

      # Build hash: [show_id, entity_type, entity_id] => status
      result = {}
      availabilities.each do |sa|
        result[[ sa.show_id, sa.available_entity_type, sa.available_entity_id ]] = sa.status
      end
      result
    end

    def count_assignments_per_member
      counts = Hash.new(0)

      # Count draft assignments
      @casting_table.casting_table_draft_assignments.each do |da|
        key = [ da.assignable_type, da.assignable_id ]
        counts[key] += 1
      end

      # Count existing (finalized) assignments
      @existing_assignments.each_value do |assignments|
        assignments.each do |a|
          key = [ a.assignable_type, a.assignable_id ]
          counts[key] += 1
        end
      end

      counts
    end

    def count_show_assignments
      counts = Hash.new(0)

      # Count draft assignments per show
      @casting_table.casting_table_draft_assignments.each do |da|
        counts[da.show_id] += 1
      end

      # Count existing assignments per show
      @existing_assignments.each do |(show_id, _, _), assignments|
        counts[show_id] += assignments.size
      end

      counts
    end

    def count_role_assignments_by_show
      # Returns hash: [show_id, role_id] => count
      # Maps assignments to the show's available roles by name to handle
      # cases where assignments use production-level roles instead of show-level roles
      counts = Hash.new(0)

      # Build a map of role name -> show's role id for each show
      role_name_to_show_role_id = {}
      @roles_by_show.each do |show_id, roles|
        role_name_to_show_role_id[show_id] = {}
        roles.each do |role|
          role_name_to_show_role_id[show_id][role.name] = role.id
        end
      end

      # Count draft assignments (map to show's role by name)
      @casting_table.casting_table_draft_assignments.includes(:role).each do |da|
        role_name = da.role.name
        show_role_id = role_name_to_show_role_id.dig(da.show_id, role_name) || da.role_id
        counts[[ da.show_id, show_role_id ]] += 1
      end

      # Count existing assignments (map to show's role by name)
      @existing_assignments.each_value do |assignments|
        assignments.each do |a|
          role_name = a.role.name
          show_role_id = role_name_to_show_role_id.dig(a.show_id, role_name) || a.role_id
          counts[[ a.show_id, show_role_id ]] += 1
        end
      end

      counts
    end

    def send_casting_notifications
      # Group assignments by person/group
      assignments_by_assignable = @casting_table.casting_table_draft_assignments
                                                 .includes(:show, :role)
                                                 .group_by { |da| [ da.assignable_type, da.assignable_id ] }

      assignments_by_assignable.each do |(type, id), assignments|
        if type == "Person"
          person = Person.find(id)
          CastingTableMailer.casting_notification(
            person: person,
            casting_table: @casting_table,
            assignments: assignments
          ).deliver_later
        end
        # For groups, we could notify group members or skip
      end
    end
  end
end
