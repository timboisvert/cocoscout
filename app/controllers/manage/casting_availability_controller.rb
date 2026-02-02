# frozen_string_literal: true

module Manage
  class CastingAvailabilityController < Manage::ManageController
    before_action :set_production, except: [ :org_index, :org_person_modal, :org_show_modal, :org_cast_person, :org_sign_up_person, :org_register_person, :org_pre_register, :org_pre_register_all, :org_set_availability ]

    def index
      # Get all future shows for this production, ordered by date
      # Load them into memory once to avoid multiple queries
      @shows = @production.shows
                          .where(canceled: false)
                          .where("date_and_time >= ?", Time.current)
                          .order(:date_and_time)
                          .to_a

      # Get effective talent pool ID (shared or own)
      effective_pool = @production.effective_talent_pool
      talent_pool_id = effective_pool&.id

      # Get all cast members with headshots eager loaded in a single query
      @people = Person
                .joins(:talent_pool_memberships)
                .where(talent_pool_memberships: { talent_pool_id: talent_pool_id })
                .includes(profile_headshots: { image_attachment: :blob })
                .distinct
                .order(:name)
                .to_a

      @groups = Group
                .joins(:talent_pool_memberships)
                .where(talent_pool_memberships: { talent_pool_id: talent_pool_id })
                .includes(profile_headshots: { image_attachment: :blob })
                .distinct
                .order(:name)
                .to_a

      @cast_members = (@people + @groups).sort_by(&:name)

      # Fetch all availabilities for these shows in one query
      # Use .map(&:id) on already-loaded array instead of .pluck which triggers another query
      show_ids = @shows.map(&:id)
      all_availabilities = ShowAvailability.where(show_id: show_ids).to_a

      # Build a hash of availabilities: { "Person_1" => { show_id => show_availability }, "Group_2" => ... }
      @availabilities = {}
      @cast_members.each do |member|
        key = "#{member.class.name}_#{member.id}"
        @availabilities[key] = {}
      end

      all_availabilities.each do |availability|
        key = "#{availability.available_entity_type}_#{availability.available_entity_id}"
        @availabilities[key] ||= {}
        @availabilities[key][availability.show_id] = availability
      end
    end

    # Returns HTML for the show availability modal
    def show_modal
      @show = @production.shows
                         .includes(
                           :location,
                           poster_attachment: :blob,
                           production: { posters: { image_attachment: :blob } }
                         )
                         .find(params[:id])

      # Get effective talent pool ID (shared or own)
      effective_pool = @production.effective_talent_pool
      talent_pool_id = effective_pool&.id

      # Get all cast members with headshots eager loaded in a single query
      @people = Person
                .joins(:talent_pool_memberships)
                .where(talent_pool_memberships: { talent_pool_id: talent_pool_id })
                .includes(profile_headshots: { image_attachment: :blob })
                .distinct
                .order(:name)
                .to_a

      @groups = Group
                .joins(:talent_pool_memberships)
                .where(talent_pool_memberships: { talent_pool_id: talent_pool_id })
                .includes(profile_headshots: { image_attachment: :blob })
                .distinct
                .order(:name)
                .to_a

      @cast_members = (@people + @groups).sort_by(&:name)

      # Fetch all availabilities for this show in one query
      show_availabilities = ShowAvailability.where(show: @show).to_a

      @availabilities = {}
      show_availabilities.each do |availability|
        key = "#{availability.available_entity_type}_#{availability.available_entity_id}"
        @availabilities[key] = availability
      end

      render partial: "manage/casting_availability/show_modal", locals: {
        show: @show,
        production: @production,
        cast_members: @cast_members,
        availabilities: @availabilities
      }
    end

    def update_show_availability
      @show = @production.shows.find(params[:id])

      # Update availabilities for each person and group
      params.each do |key, value|
        # Match pattern: availability_Person_123 or availability_Group_456
        next unless key.match?(/^availability_(Person|Group)_(\d+)$/)

        matches = key.match(/^availability_(Person|Group)_(\d+)$/)
        entity_type = matches[1]
        entity_id = matches[2].to_i

        # Find the entity (Person or Group)
        entity = if entity_type == "Person"
                   Person.find(entity_id)
        else
                   Group.find(entity_id)
        end

        availability = entity.show_availabilities.find_or_initialize_by(show: @show)

        if value == "available"
          availability.available!
        elsif value == "unavailable"
          availability.unavailable!
        end

        availability.save
      end

      respond_to do |format|
        format.html { redirect_to manage_casting_availability_path(@production), notice: "Availability updated" }
        format.json { render json: { success: true } }
      end
    end

    def org_index
      # Time filter parameter (default 3 months)
      @months = params[:months]&.to_i || 3
      @months = 3 unless [ 3, 6, 12 ].include?(@months)

      end_date = @months.months.from_now

      # Production filter parameter (default all)
      @all_productions = Current.organization.productions.type_in_house
                                 .includes(:talent_pools)
                                 .order(:name)
                                 .to_a

      @selected_production_id = params[:production_id]&.to_i
      @selected_production = @all_productions.find { |p| p.id == @selected_production_id }

      # Filter productions based on selection
      @productions = @selected_production ? [ @selected_production ] : @all_productions

      # Get all future shows within time range, grouped by production
      @shows_by_production = {}
      all_show_ids = []

      @productions.each do |production|
        shows = production.shows
                          .where(canceled: false)
                          .where("date_and_time >= ?", Time.current)
                          .where("date_and_time <= ?", end_date)
                          .includes(:production)
                          .order(:date_and_time)
                          .to_a
        @shows_by_production[production.id] = shows
        all_show_ids.concat(shows.map(&:id))
      end

      # Collect members from talent pools (filtered by production if selected)
      @members = collect_all_members

      # Build member-to-production mapping for talent pool membership
      @member_productions = build_member_productions_lookup

      # Build availability lookup: {[show_id, member_type, member_id] => status}
      @availability = build_availability_lookup(all_show_ids)

      # Build cast assignments lookup
      @cast_assignments = build_cast_assignments_lookup(all_show_ids)

      # Build sign-up registrations lookup
      @sign_up_registrations = build_sign_up_registrations_lookup(all_show_ids)
    end

    def org_person_modal
      @member = find_member(params[:id], params[:type])
      @filter_by = params[:filter_by] || "date"

      # Get time range
      months = params[:months]&.to_i || 3
      months = 3 unless [ 3, 6, 12 ].include?(months)
      end_date = months.months.from_now

      # Get shows data for this person
      @shows_data = build_person_shows_data(@member, end_date)

      # Build lookup for ALL roles, role counts, and sign-up forms per show
      @all_roles_by_show = {}
      @role_counts_by_show = {}
      @sign_up_forms_by_show = {}
      @sign_up_form_open_by_show = {}

      @shows_data.each do |show_data|
        show = show_data[:show]
        roles = show.available_roles.order(:position).to_a
        @all_roles_by_show[show.id] = roles

        # Build role counts for this show
        roles.each do |role|
          @role_counts_by_show[[ show.id, role.id ]] = ShowPersonRoleAssignment.where(show: show, role: role).count
        end

        sign_up_form = find_sign_up_form_for_show(show)
        @sign_up_forms_by_show[show.id] = sign_up_form
        @sign_up_form_open_by_show[show.id] = sign_up_form && sign_up_form_open?(sign_up_form, show)
      end

      render partial: "manage/org_availability/person_modal"
    end

    def org_show_modal
      @show = Show.includes(:production, :location).find(params[:id])
      @production = @show.production

      # Get all members with their availability for this show
      @members_data = build_show_members_data(@show)

      # Get ALL roles for this show (not just open ones)
      @all_roles = @show.available_roles.order(:position).to_a

      # Build role counts (how many are assigned per role)
      @role_counts = {}
      @all_roles.each do |role|
        @role_counts[role.id] = ShowPersonRoleAssignment.where(show: @show, role: role).count
      end

      # Get sign-up form for this show (if any) - even if not open yet
      @sign_up_form = find_sign_up_form_for_show(@show)

      # Check if sign-up form is currently open
      @sign_up_form_open = @sign_up_form && sign_up_form_open?(@sign_up_form, @show)

      render partial: "manage/org_availability/show_modal"
    end

    def org_cast_person
      show = Show.find(params[:show_id])
      role = Role.find(params[:role_id])
      person = Person.find(params[:person_id])

      assignment = ShowPersonRoleAssignment.create!(
        show: show,
        role: role,
        assignable: person
      )

      render json: { success: true, assignment_id: assignment.id }
    rescue ActiveRecord::RecordInvalid => e
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end

    def org_sign_up_person
      # Legacy method - redirect to register_person
      register_person
    end

    def org_register_person
      show = Show.find(params[:show_id])
      person = Person.find(params[:person_id])
      slot_id = params[:slot_id]

      sign_up_form = find_sign_up_form_for_show(show)
      unless sign_up_form
        render json: { success: false, error: "No sign-up form for this show" }, status: :unprocessable_entity
        return
      end

      instance = sign_up_form.sign_up_form_instances.find_by(show: show)
      unless instance
        render json: { success: false, error: "No sign-up form instance for this show" }, status: :unprocessable_entity
        return
      end

      # Helper to check if slot has capacity
      slot_has_capacity = ->(s) {
        current = s.sign_up_registrations.where(status: %w[confirmed waitlisted]).count
        current < (s.capacity || 1)
      }

      # If slot_id is provided, use that specific slot
      # Otherwise, find first available slot (for open_list or legacy calls)
      if slot_id.present?
        slot = instance.sign_up_slots.find_by(id: slot_id)
        unless slot
          render json: { success: false, error: "Slot not found" }, status: :unprocessable_entity
          return
        end
        unless slot_has_capacity.call(slot)
          render json: { success: false, error: "Slot is full" }, status: :unprocessable_entity
          return
        end
      else
        slot = instance.sign_up_slots.order(:position).find { |s| slot_has_capacity.call(s) }
        unless slot
          render json: { success: false, error: "No available slots" }, status: :unprocessable_entity
          return
        end
      end

      next_position = slot.sign_up_registrations.maximum(:position).to_i + 1
      registration = slot.sign_up_registrations.create!(
        person: person,
        status: "confirmed",
        registered_at: Time.current,
        position: next_position
      )

      SignUpRegistrantNotificationJob.perform_later(registration.id, :confirmation)

      render json: { success: true, registration_id: registration.id }
    rescue ActiveRecord::RecordInvalid => e
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end

    def org_pre_register
      show = Show.find(params[:show_id])
      person = Person.find(params[:person_id])
      send_email = params[:send_email] == "true" || params[:send_email] == true

      sign_up_form = find_sign_up_form_for_show(show)
      unless sign_up_form
        render json: { success: false, error: "No sign-up form for this show" }, status: :unprocessable_entity
        return
      end

      # Find or create instance for the show
      instance = sign_up_form.sign_up_form_instances.find_by(show: show)
      instance ||= sign_up_form.sign_up_form_instances.create!(show: show)

      # Create queued registration
      registration = instance.register_to_queue!(person: person)

      # The register_to_queue! method already sends an email, but we can control this
      # If send_email is explicitly false, we might want different behavior
      # For now, the notification is always sent by register_to_queue!

      render json: { success: true, registration_id: registration.id }
    rescue StandardError => e
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end

    def org_pre_register_all
      show = Show.find(params[:show_id])
      person_ids = params[:person_ids] || []

      sign_up_form = find_sign_up_form_for_show(show)
      unless sign_up_form
        render json: { success: false, error: "No sign-up form for this show" }, status: :unprocessable_entity
        return
      end

      # Find or create instance for the show
      instance = sign_up_form.sign_up_form_instances.find_by(show: show)
      instance ||= sign_up_form.sign_up_form_instances.create!(show: show)

      # Helper to check if slot has capacity
      slot_has_capacity = ->(s) {
        current = s.sign_up_registrations.where(status: %w[confirmed waitlisted]).count
        current < (s.capacity || 1)
      }

      registered_count = 0
      errors = []

      person_ids.each do |person_id|
        begin
          person = Person.find(person_id)

          # Skip if already registered
          existing = SignUpRegistration.joins(:sign_up_slot)
                                       .where(sign_up_slots: { sign_up_form_instance_id: instance.id })
                                       .where(person: person, status: %w[confirmed waitlisted queued])
                                       .exists?
          next if existing

          # Find first available slot
          slot = instance.sign_up_slots.order(:position).find { |s| slot_has_capacity.call(s) }
          next unless slot

          # Create registration
          next_position = slot.sign_up_registrations.maximum(:position).to_i + 1
          slot.sign_up_registrations.create!(
            person: person,
            status: "confirmed",
            registered_at: Time.current,
            position: next_position
          )

          registered_count += 1
        rescue => e
          errors << "#{person_id}: #{e.message}"
        end
      end

      if registered_count > 0
        render json: { success: true, registered_count: registered_count, errors: errors }
      else
        render json: { success: false, error: "No people were registered", errors: errors }, status: :unprocessable_entity
      end
    end

    def org_set_availability
      show = Show.find(params[:show_id])
      person = Person.find(params[:person_id])
      status = params[:status]

      unless %w[available unavailable].include?(status)
        render json: { success: false, error: "Invalid status" }, status: :unprocessable_entity
        return
      end

      availability = ShowAvailability.find_or_initialize_by(show: show, available_entity: person)
      availability.status = status
      availability.save!

      render json: { success: true }
    rescue ActiveRecord::RecordInvalid => e
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end

    private

    def set_production
      unless Current.organization
        redirect_to select_organization_path, alert: "Please select an organization first."
        return
      end
      @production = Current.organization.productions.find(params.expect(:production_id))
    end

    def collect_all_members
      person_ids = Set.new
      group_ids = Set.new

      # Use @productions which is already filtered by production selection
      @productions.each do |production|
        pool = production.effective_talent_pool
        next unless pool

        pool.talent_pool_memberships.each do |membership|
          if membership.member_type == "Person"
            person_ids << membership.member_id
          else
            group_ids << membership.member_id
          end
        end
      end

      people = Person.where(id: person_ids.to_a)
                     .includes(profile_headshots: { image_attachment: :blob })
                     .order(:name)
      groups = Group.where(id: group_ids.to_a)
                    .includes(profile_headshots: { image_attachment: :blob })
                    .order(:name)

      (people.to_a + groups.to_a).sort_by { |m| m.name.downcase }
    end

    def build_availability_lookup(show_ids)
      return {} if show_ids.empty?

      availabilities = ShowAvailability.where(show_id: show_ids)

      result = {}
      availabilities.each do |sa|
        result[[ sa.show_id, sa.available_entity_type, sa.available_entity_id ]] = sa.status
      end
      result
    end

    def build_cast_assignments_lookup(show_ids)
      return {} if show_ids.empty?

      assignments = ShowPersonRoleAssignment.where(show_id: show_ids).includes(:role)

      result = {}
      assignments.each do |a|
        key = [ a.show_id, a.assignable_type, a.assignable_id ]
        result[key] ||= []
        result[key] << a
      end
      result
    end

    def build_sign_up_registrations_lookup(show_ids)
      return {} if show_ids.empty?

      registrations = SignUpRegistration
                      .joins(sign_up_slot: { sign_up_form_instance: :show })
                      .where(shows: { id: show_ids })
                      .where.not(status: "cancelled")
                      .includes(:person, sign_up_slot: { sign_up_form_instance: :show })

      result = {}
      registrations.each do |r|
        next unless r.person_id

        show_id = r.sign_up_slot.sign_up_form_instance.show_id
        key = [ show_id, "Person", r.person_id ]
        result[key] ||= []
        result[key] << r
      end
      result
    end

    def find_member(id, type)
      if type == "Group"
        Group.includes(profile_headshots: { image_attachment: :blob }).find(id)
      else
        Person.includes(profile_headshots: { image_attachment: :blob }).find(id)
      end
    end

    def build_person_shows_data(member, end_date)
      member_type = member.class.name
      member_id = member.id

      # Get all shows this person might be relevant for
      all_shows = []
      @productions ||= Current.organization.productions.type_in_house.to_a

      @productions.each do |production|
        pool = production.effective_talent_pool
        next unless pool

        # Check if member is in this pool
        in_pool = pool.talent_pool_memberships.exists?(member_type: member_type, member_id: member_id)
        next unless in_pool

        shows = production.shows
                          .where(canceled: false)
                          .where("date_and_time >= ?", Time.current)
                          .where("date_and_time <= ?", end_date)
                          .includes(:production)
                          .order(:date_and_time)
        all_shows.concat(shows.to_a)
      end

      # Get availability for all these shows
      show_ids = all_shows.map(&:id)
      availabilities = ShowAvailability.where(
        show_id: show_ids,
        available_entity_type: member_type,
        available_entity_id: member_id
      ).index_by(&:show_id)

      # Get cast assignments with roles
      cast_assignments = ShowPersonRoleAssignment.where(
        show_id: show_ids,
        assignable_type: member_type,
        assignable_id: member_id
      ).includes(:role).group_by(&:show_id)

      # Get sign-up registrations (only for Person)
      sign_up_registrations = {}
      if member_type == "Person"
        registrations = SignUpRegistration
                        .joins(sign_up_slot: { sign_up_form_instance: :show })
                        .where(shows: { id: show_ids })
                        .where(person_id: member_id)
                        .where.not(status: "cancelled")
                        .includes(sign_up_slot: { sign_up_form_instance: :show })

        registrations.each do |r|
          show_id = r.sign_up_slot.sign_up_form_instance.show_id
          sign_up_registrations[show_id] = r
        end
      end

      # Build data array
      all_shows.map do |show|
        avail = availabilities[show.id]
        cast = cast_assignments[show.id]
        registration = sign_up_registrations[show.id]
        {
          show: show,
          availability: avail&.status,
          is_cast: cast.present?,
          cast_roles: cast&.map { |a| a.role.name } || [],
          is_signed_up: registration.present?,
          registration: registration
        }
      end
    end

    def build_show_members_data(show)
      production = show.production
      pool = production.effective_talent_pool
      return [] unless pool

      # Get all members from the talent pool
      memberships = pool.talent_pool_memberships.includes(member: { profile_headshots: { image_attachment: :blob } })

      # Get availability for this show
      availabilities = ShowAvailability.where(show: show).index_by { |a| [ a.available_entity_type, a.available_entity_id ] }

      # Get cast assignments
      cast_assignments = ShowPersonRoleAssignment.where(show: show).includes(:role)
      cast_lookup = cast_assignments.group_by { |a| [ a.assignable_type, a.assignable_id ] }

      # Get sign-up registrations with slot details
      sign_up_lookup = {}
      sign_up_form = find_sign_up_form_for_show(show)
      if sign_up_form
        instance = sign_up_form.sign_up_form_instances.find_by(show: show)
        if instance
          registrations = instance.sign_up_registrations
                                  .joins(:sign_up_slot)
                                  .includes(:sign_up_slot)
                                  .where.not(status: "cancelled")
                                  .where.not(person_id: nil)
          registrations.each do |r|
            sign_up_lookup[[ "Person", r.person_id ]] = r
          end
        end
      end

      # Build data array
      memberships.map do |membership|
        member = membership.member
        member_key = [ member.class.name, member.id ]
        avail = availabilities[member_key]
        registration = sign_up_lookup[member_key]
        {
          member: member,
          availability: avail&.status,
          is_cast: cast_lookup[member_key].present?,
          cast_roles: cast_lookup[member_key]&.map { |a| a.role.name } || [],
          is_signed_up: registration.present?,
          registration: registration
        }
      end.sort_by { |d| d[:member].name.downcase }
    end

    def find_sign_up_form_for_show(show)
      # Find a sign-up form via the form instance linked to this show
      SignUpFormInstance.where(show: show).first&.sign_up_form
    end

    def role_fully_filled?(role, show)
      current_count = ShowPersonRoleAssignment.where(show: show, role: role).count
      current_count >= (role.quantity || 1)
    end

    def sign_up_form_open?(sign_up_form, show)
      return false unless sign_up_form

      instance = sign_up_form.sign_up_form_instances.find_by(show: show)
      return false unless instance

      # Check if the form is currently open based on its schedule
      now = Time.current
      opens_at = instance.opens_at || sign_up_form.default_opens_at
      closes_at = instance.closes_at || sign_up_form.default_closes_at

      # If no opens_at defined, consider it open
      return true if opens_at.nil?

      # Check if we're within the open window
      opened = now >= opens_at
      closed = closes_at.present? && now > closes_at

      opened && !closed
    end

    def build_member_productions_lookup
      # Returns: { [member_type, member_id] => Set of production_ids }
      result = Hash.new { |h, k| h[k] = Set.new }

      @productions.each do |production|
        pool = production.effective_talent_pool
        next unless pool

        pool.talent_pool_memberships.each do |membership|
          key = [ membership.member_type, membership.member_id ]
          result[key] << production.id
        end
      end

      result
    end
  end
end
