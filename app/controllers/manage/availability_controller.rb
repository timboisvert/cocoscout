# frozen_string_literal: true

module Manage
  class AvailabilityController < Manage::ManageController
    before_action :set_production

    def index
      # Get all future shows for this production, ordered by date
      # Load them into memory once to avoid multiple queries
      @shows = @production.shows
                          .where(canceled: false)
                          .where("date_and_time >= ?", Time.current)
                          .order(:date_and_time)
                          .to_a

      # Get talent pool IDs in a single query
      talent_pool_ids = @production.talent_pool_ids

      # Get all cast members with headshots eager loaded in a single query
      @people = Person
                .joins(:talent_pool_memberships)
                .where(talent_pool_memberships: { talent_pool_id: talent_pool_ids })
                .includes(profile_headshots: { image_attachment: :blob })
                .distinct
                .order(:name)
                .to_a

      @groups = Group
                .joins(:talent_pool_memberships)
                .where(talent_pool_memberships: { talent_pool_id: talent_pool_ids })
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

    def show
      # Get the specific show with its poster and production's posters eager loaded
      @show = @production.shows
                         .includes(
                           :location,
                           poster_attachment: :blob,
                           production: { posters: { image_attachment: :blob } }
                         )
                         .find(params[:id])

      # Get talent pool IDs in a single query
      talent_pool_ids = @production.talent_pool_ids

      # Get all cast members with headshots eager loaded in a single query
      @people = Person
                .joins(:talent_pool_memberships)
                .where(talent_pool_memberships: { talent_pool_id: talent_pool_ids })
                .includes(profile_headshots: { image_attachment: :blob })
                .distinct
                .order(:name)
                .to_a

      @groups = Group
                .joins(:talent_pool_memberships)
                .where(talent_pool_memberships: { talent_pool_id: talent_pool_ids })
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

      # Track edit mode
      @edit_mode = params[:edit] == "true"
    end

    def request_availability
      # Get all future shows for this production - load into memory once
      @shows = @production.shows
                          .where(canceled: false)
                          .where("date_and_time >= ?", Time.current)
                          .order(:date_and_time)
                          .to_a
      show_ids = @shows.map(&:id)

      # Get the single talent pool for this production
      @talent_pool = @production.talent_pool

      # Get all talent pool memberships in one query
      all_memberships = TalentPoolMembership
                        .where(talent_pool_id: @talent_pool.id)
                        .pluck(:member_id, :member_type, :talent_pool_id)

      # Get unique person IDs and group IDs from memberships
      person_ids_in_pools = all_memberships.select { |_, type, _| type == "Person" }.map(&:first).uniq
      group_ids_in_pools = all_memberships.select { |_, type, _| type == "Group" }.map(&:first).uniq

      # Load people and groups in bulk (no headshots needed - we just need name)
      @cast_members = Person.where(id: person_ids_in_pools).order(:name).to_a
      @cast_groups = Group.where(id: group_ids_in_pools).order(:name).to_a

      # Fetch all availabilities in one query - both Person and Group types
      all_availabilities_raw = ShowAvailability
                               .where(show_id: show_ids)
                               .where(available_entity_type: %w[Person Group])
                               .pluck(:available_entity_id, :available_entity_type, :show_id)

      # Build separate lookups for people and groups
      person_availabilities = all_availabilities_raw
                              .select { |_, type, _| type == "Person" }
                              .group_by(&:first)
                              .transform_values { |rows| rows.map(&:last) }

      group_availabilities = all_availabilities_raw
                             .select { |_, type, _| type == "Group" }
                             .group_by(&:first)
                             .transform_values { |rows| rows.map(&:last) }

      # Build availability data for JavaScript - includes both people and groups
      @availability_data = []

      @cast_members.each do |person|
        @availability_data << {
          id: person.id,
          name: person.name,
          type: "Person",
          submitted_show_ids: person_availabilities[person.id] || [],
          talent_pool_ids: [ @talent_pool.id ]
        }
      end

      @cast_groups.each do |group|
        @availability_data << {
          id: group.id,
          name: group.name,
          type: "Group",
          submitted_show_ids: group_availabilities[group.id] || [],
          talent_pool_ids: [ @talent_pool.id ]
        }
      end

      # Sort by name for consistent ordering
      @availability_data.sort_by! { |m| m[:name].downcase }

      # Determine which members are up to date (for initial render)
      sorted_show_ids = show_ids.sort

      @members_needing_update = @availability_data.reject do |member|
        submitted = (member[:submitted_show_ids] || []).sort
        submitted == sorted_show_ids
      end

      @members_up_to_date = @availability_data.select do |member|
        submitted = (member[:submitted_show_ids] || []).sort
        submitted == sorted_show_ids
      end

      # Generate default message with all shows
      @default_message = generate_default_message(@shows)
    end

    def handle_request_availability
      recipient_type = params[:recipient_type]
      talent_pool_id = params[:talent_pool_id]
      person_ids = params[:person_ids] || []
      group_ids = params[:group_ids] || []
      message_template = params[:message]
      selected_show_ids = params[:show_ids] || []

      # Get shows - either selected ones or all future shows
      shows = if selected_show_ids.present? && selected_show_ids.any?
                @production.shows.where(id: selected_show_ids, canceled: false)
      else
                @production.shows.where(canceled: false).where("date_and_time >= ?", Time.current)
      end
      show_ids_sorted = shows.pluck(:id).sort

      # Get the talent pool for this production
      talent_pool = @production.talent_pool

      # Determine recipient IDs based on recipient_type
      if recipient_type == "all" && talent_pool
        memberships = TalentPoolMembership.where(talent_pool_id: talent_pool.id)
        recipient_person_ids = memberships.where(member_type: "Person").pluck(:member_id).uniq
        recipient_group_ids = memberships.where(member_type: "Group").pluck(:member_id).uniq
      elsif recipient_type == "cast" && talent_pool_id.present?
        memberships = TalentPoolMembership.where(talent_pool_id: talent_pool_id)
        recipient_person_ids = memberships.where(member_type: "Person").pluck(:member_id)
        recipient_group_ids = memberships.where(member_type: "Group").pluck(:member_id)
      elsif recipient_type == "specific"
        recipient_person_ids = person_ids.map(&:to_i)
        recipient_group_ids = group_ids.map(&:to_i)
      else
        recipient_person_ids = []
        recipient_group_ids = []
      end

      # For non-specific selections, filter out those who are already up to date
      unless recipient_type == "specific"
        # Fetch submitted availabilities in bulk
        person_submitted = ShowAvailability
                           .where(show_id: show_ids_sorted, available_entity_type: "Person", available_entity_id: recipient_person_ids)
                           .group(:available_entity_id)
                           .pluck(:available_entity_id, Arel.sql("STRING_AGG(show_id::text, ',')"))
                           .to_h
                           .transform_values { |ids| ids.split(",").map(&:to_i).sort }

        group_submitted = ShowAvailability
                          .where(show_id: show_ids_sorted, available_entity_type: "Group", available_entity_id: recipient_group_ids)
                          .group(:available_entity_id)
                          .pluck(:available_entity_id, Arel.sql("STRING_AGG(show_id::text, ',')"))
                          .to_h
                          .transform_values { |ids| ids.split(",").map(&:to_i).sort }

        # Filter to only those who need updates
        recipient_person_ids = recipient_person_ids.reject { |id| person_submitted[id] == show_ids_sorted }
        recipient_group_ids = recipient_group_ids.reject { |id| group_submitted[id] == show_ids_sorted }
      end

      # Load recipients
      people = Person.includes(:user).where(id: recipient_person_ids)
      groups = Group.where(id: recipient_group_ids)

      # Fetch submitted show IDs for all recipients in bulk for personalized messages
      person_submitted_shows = ShowAvailability
                               .where(show_id: show_ids_sorted, available_entity_type: "Person", available_entity_id: recipient_person_ids)
                               .pluck(:available_entity_id, :show_id)
                               .group_by(&:first)
                               .transform_values { |rows| rows.map(&:last) }

      group_submitted_shows = ShowAvailability
                              .where(show_id: show_ids_sorted, available_entity_type: "Group", available_entity_id: recipient_group_ids)
                              .pluck(:available_entity_id, :show_id)
                              .group_by(&:first)
                              .transform_values { |rows| rows.map(&:last) }

      email_count = 0

      # Send emails to people
      people.each do |person|
        next unless person.user

        submitted_ids = person_submitted_shows[person.id] || []
        pending_shows = shows.where.not(id: submitted_ids)
        next if pending_shows.empty?

        personalized_message = generate_personalized_message(pending_shows, message_template)
        Manage::AvailabilityMailer.request_availability(person, @production, personalized_message).deliver_later
        email_count += 1
      end

      # Send emails to groups (via their email)
      groups.each do |group|
        submitted_ids = group_submitted_shows[group.id] || []
        pending_shows = shows.where.not(id: submitted_ids)
        next if pending_shows.empty?

        personalized_message = generate_personalized_message(pending_shows, message_template)
        Manage::AvailabilityMailer.request_availability_for_group(group, @production,
                                                                  personalized_message).deliver_later
        email_count += 1
      end

      redirect_to manage_production_availability_index_path(@production),
                  notice: "Availability request sent to #{email_count} #{'recipient'.pluralize(email_count)}"
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

      redirect_to manage_production_availability_path(@production, @show), notice: "Availability updated"
    end

    private

    def set_production
      @production = Current.organization.productions.find(params.expect(:production_id))
    end

    def generate_default_message(shows)
      shows_list = shows.map do |show|
        base = "• #{show.event_type.titleize} on #{show.date_and_time.strftime('%A, %B %-d, %Y')} at #{show.date_and_time.strftime('%-l:%M %p')}"
        base += " (#{show.secondary_name})" if show.secondary_name.present?
        base
      end.join("\n")

      <<~MESSAGE
        Please submit your availability for the following upcoming #{@production.name} shows & events:

        #{shows_list}

        You can update your availability by visiting:
        #{my_availability_url(host: request.host_with_port, protocol: request.protocol.chomp('://'))}
      MESSAGE
    end

    def generate_personalized_message(pending_shows, template)
      # Generate the personalized shows list for this specific person
      personalized_shows_list = pending_shows.map do |show|
        "• #{show.date_and_time.strftime('%A, %B %d, %Y at %-l:%M %p')} - #{show.event_type.titleize}"
      end.join("\n")

      # Generate the default shows list pattern to find in template
      default_shows_list = @production.shows
                                      .where(canceled: false)
                                      .where("date_and_time >= ?", Time.current)
                                      .order(:date_and_time)
                                      .map { |show| "• #{show.date_and_time.strftime('%A, %B %d, %Y at %-l:%M %p')} - #{show.event_type.titleize}" }
                                      .join("\n")

      # Replace the default shows list with the personalized one
      template.gsub(default_shows_list, personalized_shows_list)
    end
  end
end
