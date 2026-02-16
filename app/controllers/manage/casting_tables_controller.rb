# frozen_string_literal: true

module Manage
  class CastingTablesController < Manage::ManageController
    before_action :ensure_user_is_manager, except: [ :index, :show ]
    before_action :set_casting_table, only: [
      :show, :update, :assign, :unassign, :summary, :finalize,
      :edit_events, :edit_members, :add_event, :remove_event, :add_member, :remove_member
    ]

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

    def update
      if @casting_table.update(casting_table_params)
        redirect_back fallback_location: manage_casting_table_path(@casting_table), notice: "Casting table updated"
      else
        redirect_back fallback_location: manage_edit_casting_table_path(@casting_table), alert: @casting_table.errors.full_messages.join(", ")
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

    # Edit events page
    def edit_events
      @shows = @casting_table.shows.order(:date_and_time).includes(:production)
      @productions = @casting_table.productions

      # For adding events (only if draft)
      if @casting_table.draft?
        # Get shows from the same productions that aren't in ANY casting table
        existing_show_ids = CastingTableEvent.pluck(:show_id)
        @available_shows = Show.where(production_id: @productions.pluck(:id))
                               .where.not(id: existing_show_ids)
                               .where("date_and_time > ?", 1.day.ago)
                               .order(:date_and_time)
                               .includes(:production)
      end

      # For each show, count draft assignments (needed for removal confirmation)
      @draft_counts = @casting_table.casting_table_draft_assignments
                                     .group(:show_id)
                                     .count
    end

    # Edit members/talent pool page
    def edit_members
      person_ids = @casting_table.casting_table_members.where(memberable_type: "Person").pluck(:memberable_id)
      group_ids = @casting_table.casting_table_members.where(memberable_type: "Group").pluck(:memberable_id)

      @people = Person.where(id: person_ids)
                      .includes(profile_headshots: { image_attachment: :blob })
                      .order(:name)
      @groups = Group.where(id: group_ids)
                     .includes(profile_headshots: { image_attachment: :blob })
                     .order(:name)

      @productions = @casting_table.productions

      # For adding members (only if draft)
      if @casting_table.draft?
        # Get all people from the org's talent pools for these productions
        existing_member_ids = @casting_table.casting_table_members.where(memberable_type: "Person").pluck(:memberable_id)
        @available_people = Current.organization.people
                                    .where.not(id: existing_member_ids)
                                    .order(:name)
                                    .limit(100)

        existing_group_ids = @casting_table.casting_table_members.where(memberable_type: "Group").pluck(:memberable_id)
        @available_groups = Current.organization.groups
                                    .where.not(id: existing_group_ids)
                                    .order(:name)
      end

      # For each member, count draft assignments (needed for removal confirmation)
      @draft_counts_by_member = {}
      @casting_table.casting_table_draft_assignments.each do |da|
        key = [ da.assignable_type, da.assignable_id ]
        @draft_counts_by_member[key] ||= 0
        @draft_counts_by_member[key] += 1
      end
    end

    # Add an event to the casting table
    def add_event
      unless @casting_table.draft?
        redirect_to manage_edit_casting_table_path(@casting_table), alert: "Cannot add events to a finalized casting table"
        return
      end

      show = Show.joins(:production)
                 .where(productions: { organization_id: Current.organization.id })
                 .find_by(id: params[:show_id])

      unless show
        redirect_to manage_edit_casting_table_path(@casting_table), alert: "Event not found"
        return
      end

      # Check if show is already in another casting table
      if CastingTableEvent.exists?(show_id: show.id)
        redirect_to manage_edit_casting_table_path(@casting_table), alert: "This event is already in a casting table"
        return
      end

      # Add to casting table
      @casting_table.casting_table_events.create!(show: show)

      # Also ensure the production is linked
      unless @casting_table.productions.include?(show.production)
        @casting_table.casting_table_productions.create!(production: show.production)
      end

      redirect_to manage_edit_casting_table_path(@casting_table), notice: "Event added to casting table"
    end

    # Remove an event from the casting table
    def remove_event
      event = @casting_table.casting_table_events.find_by(show_id: params[:show_id])

      unless event
        redirect_to manage_edit_casting_table_path(@casting_table), alert: "Event not found in casting table"
        return
      end

      # If draft, delete any draft assignments for this show
      if @casting_table.draft?
        deleted_count = @casting_table.casting_table_draft_assignments.where(show_id: params[:show_id]).delete_all
        event.destroy
        notice = deleted_count > 0 ? "Event removed along with #{deleted_count} draft assignment(s)" : "Event removed from casting table"
      else
        # If finalized, just unlink the event (real assignments stay)
        event.destroy
        notice = "Event removed from casting table (existing assignments preserved)"
      end

      redirect_to manage_edit_casting_table_path(@casting_table), notice: notice
    end

    # Add a member to the talent pool
    def add_member
      unless @casting_table.draft?
        redirect_to manage_casting_table_edit_members_path(@casting_table), alert: "Cannot add members to a finalized casting table"
        return
      end

      memberable_type = params[:memberable_type]
      memberable_id = params[:memberable_id]

      unless %w[Person Group].include?(memberable_type)
        redirect_to manage_casting_table_edit_members_path(@casting_table), alert: "Invalid member type"
        return
      end

      # Verify the member belongs to this organization
      memberable = if memberable_type == "Person"
        Current.organization.people.find_by(id: memberable_id)
      else
        Current.organization.groups.find_by(id: memberable_id)
      end

      unless memberable
        redirect_to manage_casting_table_edit_members_path(@casting_table), alert: "Member not found"
        return
      end

      # Check if already in this casting table
      if @casting_table.casting_table_members.exists?(memberable_type: memberable_type, memberable_id: memberable_id)
        redirect_to manage_casting_table_edit_members_path(@casting_table), alert: "Member already in casting table"
        return
      end

      @casting_table.casting_table_members.create!(memberable: memberable)

      redirect_to manage_casting_table_edit_members_path(@casting_table), notice: "#{memberable.name} added to talent pool"
    end

    # Remove a member from the talent pool
    def remove_member
      member = @casting_table.casting_table_members.find_by(
        memberable_type: params[:memberable_type],
        memberable_id: params[:memberable_id]
      )

      unless member
        redirect_to manage_casting_table_edit_members_path(@casting_table), alert: "Member not found in casting table"
        return
      end

      # If draft, delete any draft assignments for this member
      if @casting_table.draft?
        deleted_count = @casting_table.casting_table_draft_assignments
                                       .where(assignable_type: params[:memberable_type], assignable_id: params[:memberable_id])
                                       .delete_all
        member.destroy
        notice = deleted_count > 0 ? "Member removed along with #{deleted_count} draft assignment(s)" : "Member removed from talent pool"
      else
        # If finalized, just unlink the member (real assignments stay)
        member.destroy
        notice = "Member removed from talent pool (existing assignments preserved)"
      end

      redirect_to manage_casting_table_edit_members_path(@casting_table), notice: notice
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
          next unless person.user.present?

          # Group assignments by production for display
          assignments_by_production = assignments.group_by { |a| a.show.production }

          # Build production names for subject
          production_names = assignments_by_production.keys.map(&:name)
          formatted_names = format_production_names_for_notification(production_names)

          # Build shows list HTML grouped by production
          shows_by_production = build_shows_by_production_html(assignments_by_production)

          rendered = ContentTemplateService.render("casting_table_notification", {
            person_name: person.first_name || "there",
            production_names: formatted_names,
            shows_by_production: shows_by_production
          })

          MessageService.send_direct(
            sender: nil,
            recipient_person: person,
            subject: rendered[:subject],
            body: rendered[:body],
            production: assignments_by_production.keys.first,
            organization: @casting_table.organization,
            system_generated: true
          )
        end
        # For groups, we could notify group members or skip
      end
    end

    def format_production_names_for_notification(names)
      case names.length
      when 0
        ""
      when 1
        names.first
      when 2
        names.join(" and ")
      else
        "#{names[0..-2].join(', ')}, and #{names.last}"
      end
    end

    def build_shows_by_production_html(assignments_by_production)
      html = ""
      assignments_by_production.each do |production, prod_assignments|
        html += "<h3>#{production.name}</h3>\n<ul>\n"
        prod_assignments.group_by(&:show).sort_by { |show, _| show.date_and_time }.each do |show, show_assignments|
          roles = show_assignments.map { |a| a.role.name }.join(", ")
          date_str = show.date_and_time.strftime("%-m/%-d/%Y %-l %p")
          html += "<li>#{date_str} (#{show.display_name}): #{roles}</li>\n"
        end
        html += "</ul>\n"
      end
      html
    end
  end
end
