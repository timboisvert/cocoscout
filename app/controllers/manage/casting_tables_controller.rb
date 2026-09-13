# frozen_string_literal: true

module Manage
  class CastingTablesController < Manage::ManageController
    before_action :ensure_user_is_manager, except: [ :index, :show ]
    before_action :set_casting_table, only: [
      :show, :update, :cell, :assign, :unassign, :summary, :finalize, :unfinalize, :resend_notifications,
      :edit_events, :edit_members, :add_event, :remove_event, :add_member, :remove_member, :destroy
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

      # Draft and already-cast assignments, grouped per cell. The FULL array per
      # key, not the first: one person legitimately holds several acts on an
      # act-based night, and taking `.first` made the rest invisible.
      @draft_assignments = @casting_table.casting_table_draft_assignments
                                          .includes(:role, :assignable)
                                          .group_by { |da| [ da.show_id, da.assignable_type, da.assignable_id ] }

      @existing_assignments = ShowPersonRoleAssignment.where(show_id: @shows.pluck(:id))
                                                       .includes(:role, :assignable)
                                                       .group_by { |a| [ a.show_id, a.assignable_type, a.assignable_id ] }

      # Load roles by show (using show.available_roles which handles custom roles)
      @roles_by_show = {}
      @lineup_numbers = {}
      @shows.each do |show|
        roles = show.available_roles.order(:position).to_a
        @roles_by_show[show.id] = roles
        @lineup_numbers[show.id] = Role.lineup_numbers_for(roles)
      end

      # Double-bookings across the org, batched — three queries however many
      # members are on the board, so the whole grid can be marked at once.
      @conflicts_by_show = {}
      @shows.each do |show|
        @conflicts_by_show[show.id] = CastingConflicts.busy_map(show: show, members: @members)
      end

      # Count assignments per member and per show
      @assignment_counts = count_assignments_per_member
      @show_assignment_counts = count_show_assignments

      # Count assignments per role per show (for capacity checking)
      @role_counts_by_show = count_role_assignments_by_show

      # Castable slots per show. Role#total_slots is 0 for an intermission, so
      # this agrees with Show#fully_cast? — summing `quantity` counted every
      # break as a slot nobody could ever fill, which is why the board's x/y and
      # the fully-cast tick disagreed with what finalize! actually does.
      @show_total_slots = {}
      @shows.each do |show|
        roles = @roles_by_show[show.id] || []
        @show_total_slots[show.id] = roles.sum(&:total_slots)
      end
    end

    def update
      if @casting_table.update(casting_table_params)
        redirect_back fallback_location: manage_casting_table_path(@casting_table), notice: "Casting table updated"
      else
        redirect_back fallback_location: manage_edit_casting_table_path(@casting_table), alert: @casting_table.errors.full_messages.join(", ")
      end
    end

    # Delete a DRAFT casting table. A draft only holds suggested (draft)
    # assignments — it never created real ShowPersonRoleAssignments (those come
    # only from finalize!) — so destroying it (cascade removes the draft
    # assignments, members, events, production links) puts everything back to how
    # it was before the table, without touching any real casting. Finalized tables
    # must be unfinalized first (which removes their real assignments).
    def destroy
      unless @casting_table.draft?
        redirect_to manage_casting_table_path(@casting_table),
                    alert: "Only draft casting tables can be deleted. Unfinalize this one first to remove its assignments, then delete it."
        return
      end

      name = @casting_table.name
      @casting_table.destroy!
      redirect_to manage_casting_tables_path,
                  notice: "Casting table “#{name}” deleted. Its suggested assignments were discarded."
    end

    # AJAX: the panel behind a cell — the lineup in order, who's in each slot,
    # what this member holds, and anything that collides tonight.
    def cell
      show, member = resolve_cell
      return if show.nil?

      render json: { picker_html: render_picker(show, member) }
    end

    # AJAX: Add a draft assignment
    def assign
      unless @casting_table.draft?
        render json: { error: "Cannot modify finalized casting table" }, status: :unprocessable_entity
        return
      end

      show, member = resolve_cell
      return if show.nil?

      role = resolve_show_role(show, params[:role_id])
      return if role.nil?

      # An intermission is not a thing anybody is cast in. Validated on the model
      # too, so every writer is covered; caught here for a readable message.
      if role.break?
        render json: { error: "#{role.name} is an intermission — there's nothing to cast." },
               status: :unprocessable_entity and return
      end

      taken = @casting_table.casting_table_draft_assignments.where(show_id: show.id, role_id: role.id).count +
              ShowPersonRoleAssignment.where(show_id: show.id, role_id: role.id).count
      if taken >= role.total_slots
        render json: { error: "#{role.name} is already full (#{role.total_slots} allowed)." },
               status: :unprocessable_entity and return
      end

      # A batch board is the likeliest place to double-book somebody, so the
      # conflict check the show board has runs here too. Unless the caller already
      # said to go ahead, it answers 409 with the same shape the conflict modal
      # reads.
      unless params[:force].to_s == "true"
        conflicts = CastingConflicts.for_member(show: show, assignable: member)
        if conflicts.any?
          render json: { conflicts: conflicts.map { |c| { kind: c.kind, message: c.message } } },
                 status: :conflict and return
        end
      end

      @casting_table.casting_table_draft_assignments.find_or_create_by!(
        show_id: show.id, role_id: role.id,
        assignable_type: member.class.name, assignable_id: member.id
      )

      render json: cell_refresh(show, member)
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # AJAX: Remove a draft assignment
    def unassign
      unless @casting_table.draft?
        render json: { error: "Cannot modify finalized casting table" }, status: :unprocessable_entity
        return
      end

      show, member = resolve_cell
      return if show.nil?

      # The role is required. Without it this picked an arbitrary one of the
      # member's assignments for the night, so on an act-based show "remove" took
      # away whichever act the database happened to return first.
      role = resolve_show_role(show, params[:role_id])
      return if role.nil?

      draft = @casting_table.casting_table_draft_assignments.find_by(
        show_id: show.id, role_id: role.id,
        assignable_type: member.class.name, assignable_id: member.id
      )

      unless draft
        render json: { error: "That assignment isn't on this table." }, status: :not_found and return
      end

      draft.destroy
      render json: cell_refresh(show, member)
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

      # Load notification history for finalized casting tables
      if @casting_table.finalized?
        # Get all notifications for the shows in this casting table
        show_ids = @casting_table.shows.pluck(:id)
        @notifications = ShowCastNotification.where(show_id: show_ids)
                                              .where(notification_type: :cast)
                                              .includes(:assignable)
                                              .order(notified_at: :desc)

        # Group by person to show notification summary
        @notified_people = @notifications.select { |n| n.assignable_type == "Person" }
                                          .group_by(&:assignable)
                                          .transform_values { |notifs| notifs.max_by(&:notified_at) }
      end
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

    def unfinalize
      unless @casting_table.finalized?
        redirect_to manage_casting_table_path(@casting_table), alert: "This casting table is not finalized"
        return
      end

      if @casting_table.unfinalize!
        redirect_to manage_casting_table_summary_path(@casting_table), notice: "Casting table reverted to draft. You can now re-finalize and send notifications."
      else
        redirect_to manage_casting_table_path(@casting_table), alert: "Error unfinalizing casting table"
      end
    end

    def resend_notifications
      unless @casting_table.finalized?
        redirect_to manage_casting_table_path(@casting_table), alert: "This casting table is not finalized"
        return
      end

      # Resend notifications to all people who were cast
      send_casting_notifications
      @casting_table.record_notifications!

      redirect_to manage_casting_table_summary_path(@casting_table), notice: "Notifications resent to all cast members!"
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

    # The (show, member) a cell request is about, checked against this table.
    # Renders the error and returns nil when either is foreign to it.
    def resolve_cell
      unless @casting_table.draft? || action_name == "cell"
        render json: { error: "This casting table is finalized." }, status: :unprocessable_entity
        return nil
      end

      show = @casting_table.shows.find_by(id: params[:show_id])
      type = params[:assignable_type]
      id = params[:assignable_id].to_i

      unless show && %w[Person Group].include?(type) &&
             @casting_table.casting_table_members.exists?(memberable_type: type, memberable_id: id)
        render json: { error: "That event or member isn't on this casting table." }, status: :unprocessable_entity
        return nil
      end

      member = type.constantize.find_by(id: id)
      if member.nil?
        render json: { error: "That member no longer exists." }, status: :unprocessable_entity
        return nil
      end

      [ show, member ]
    end

    # Resolve a posted role id against THIS show's current lineup.
    #
    # The old scoping accepted any role belonging to one of the table's
    # productions — and a show's custom lineup roles carry production_id too, so a
    # role from a DIFFERENT show's lineup passed. It rendered nowhere but still
    # counted, wedging progress past 100%. A stale tab is the ordinary way that
    # happens: the board serves production role ids until a show materializes its
    # own copies, so those remap by match key and the open tab keeps working.
    def resolve_show_role(show, role_id)
      role = show.available_roles.find_by(id: role_id)
      return role if role

      source = Role.joins(:production)
                   .where(productions: { organization_id: Current.organization.id })
                   .find_by(id: role_id)
      if source && show.use_custom_roles? && source.show_id.nil? && source.production_id == show.production_id
        key = Role.match_key_for(source, source.siblings.to_a)
        target = Role.match_keys_for(show.available_roles.to_a)[key]
        return target if target
      end

      render json: { error: "This show's lineup has changed — reload the page and try again." },
             status: :unprocessable_entity
      nil
    end

    def cell_for(show, member)
      CastingTableCell.new(casting_table: @casting_table, show: show, member: member)
    end

    def render_picker(show, member)
      render_to_string(partial: "manage/casting_tables/cell_picker",
                       locals: { cell: cell_for(show, member) }, formats: [ :html ])
    end

    # Everything the board needs to redraw after a change: the cell itself, the
    # reopened picker, and the three tallies. Rendered server-side rather than
    # patched up in JavaScript — the old client-side surgery guessed at role
    # identity by name and could not show a second act at all.
    def cell_refresh(show, member)
      drafts = @casting_table.casting_table_draft_assignments
                             .where(show_id: show.id, assignable_type: member.class.name, assignable_id: member.id)
                             .includes(:role).to_a
      existing = ShowPersonRoleAssignment
                 .where(show_id: show.id, assignable_type: member.class.name, assignable_id: member.id)
                 .includes(:role).to_a
      roles = show.available_roles.order(:position).to_a
      total_slots = roles.sum(&:total_slots)
      show_count = @casting_table.casting_table_draft_assignments.where(show_id: show.id).count +
                   ShowPersonRoleAssignment.where(show_id: show.id).count

      {
        cell_html: render_to_string(
          partial: "manage/casting_tables/cell_content",
          locals: { drafts: drafts, existing: existing, show: show,
                    numbers: Role.lineup_numbers_for(roles),
                    availability: availability_for(show, member),
                    conflicted: CastingConflicts.for_member(show: show, assignable: member).any?,
                    clickable: @casting_table.draft? },
          formats: [ :html ]
        ),
        picker_html: render_picker(show, member),
        show_id: show.id,
        show_count: show_count,
        show_total_slots: total_slots,
        show_fully_cast: total_slots.positive? && show_count >= total_slots,
        member_key: "#{member.class.name}_#{member.id}",
        member_count: member_draft_count(member),
        total_count: @casting_table.casting_table_draft_assignments.count
      }
    end

    def member_draft_count(member)
      @casting_table.casting_table_draft_assignments
                    .where(assignable_type: member.class.name, assignable_id: member.id).count
    end

    def availability_for(show, member)
      ShowAvailability.find_by(show_id: show.id, available_entity_type: member.class.name,
                               available_entity_id: member.id)&.status || "unset"
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

    # [show_id, role_id] => how many of that slot are taken.
    #
    # Assignments are matched to the show's lineup by Role#match_key — the name
    # plus its ordinal among same-named siblings — because an assignment may
    # still point at a production-level role the show has since copied. Matching
    # on the bare NAME (as this did) folded the two "Magic" acts of an act-based
    # lineup onto one slot, so one read 2/1 and refused further casting while the
    # other sat empty.
    def count_role_assignments_by_show
      counts = Hash.new(0)
      keys_by_show = @roles_by_show.transform_values { |roles| Role.match_keys_for(roles) }

      resolve = lambda do |show_id, role|
        by_key = keys_by_show[show_id] or return role.id
        return role.id if by_key.value?(role)

        by_key[Role.match_key_for(role, role.siblings.to_a)]&.id || role.id
      end

      @casting_table.casting_table_draft_assignments.includes(:role).each do |da|
        counts[[ da.show_id, resolve.call(da.show_id, da.role) ]] += 1
      end

      @existing_assignments.each_value do |assignments|
        assignments.each { |a| counts[[ a.show_id, resolve.call(a.show_id, a.role) ]] += 1 }
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
