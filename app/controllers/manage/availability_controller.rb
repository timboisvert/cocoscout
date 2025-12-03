class Manage::AvailabilityController < Manage::ManageController
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

    # Get all talent pools for this production
    @talent_pools = @production.talent_pools.order(:name).to_a
    talent_pool_ids = @talent_pools.map(&:id)

    # Get all cast members (people only for this view) with eager loading
    @cast_members = Person
      .joins(:talent_pool_memberships)
      .where(talent_pool_memberships: { talent_pool_id: talent_pool_ids })
      .includes(profile_headshots: { image_attachment: :blob })
      .distinct
      .order(:name)
      .to_a

    # Fetch all availabilities in one query and build lookup
    all_availabilities = ShowAvailability
      .where(show_id: show_ids, available_entity_type: "Person")
      .pluck(:available_entity_id, :show_id)
      .group_by(&:first)
      .transform_values { |pairs| pairs.map(&:last).sort }

    # Determine which cast members are up to date
    @up_to_date_person_ids = @cast_members.select do |person|
      submitted_show_ids = all_availabilities[person.id] || []
      submitted_show_ids == show_ids.sort
    end.map(&:id)

    # Split cast members into those needing updates and those up to date
    @cast_members_needing_update = @cast_members.reject { |p| @up_to_date_person_ids.include?(p.id) }
    @cast_members_up_to_date = @cast_members.select { |p| @up_to_date_person_ids.include?(p.id) }

    # Generate default message with all shows
    @default_message = generate_default_message(@shows)
  end

  def handle_request_availability
    recipient_type = params[:recipient_type]
    cast_id = params[:cast_id]
    person_ids = params[:person_ids] || []
    message_template = params[:message]
    selected_show_ids = params[:show_ids] || []

    # Get shows - either selected ones or all future shows
    shows = if selected_show_ids.any?
      @production.shows.where(id: selected_show_ids, canceled: false)
    else
      @production.shows.where(canceled: false).where("date_and_time >= ?", Time.current)
    end

    # Determine recipients based on recipient_type
    all_recipients = if recipient_type == "all"
      @production.talent_pools.flat_map(&:people).uniq
    elsif recipient_type == "cast"
      TalentPool.find(cast_id).people
    elsif recipient_type == "specific"
      Person.where(id: person_ids)
    else
      []
    end

    # Filter out people who are already up to date (unless specifically selected)
    recipients = if recipient_type == "specific"
      # For specific selection, only send to those explicitly checked (disabled ones can't be checked)
      all_recipients
    else
      # For "all" or "cast", exclude people who are up to date
      all_recipients.reject do |person|
        submitted_show_ids = person.show_availabilities.where(show: shows).pluck(:show_id)
        submitted_show_ids.sort == shows.pluck(:id).sort
      end
    end

    # Send emails
    recipients.each do |person|
      if person.user
        # Get shows this person hasn't submitted availability for
        submitted_show_ids = person.show_availabilities.where(show: shows).pluck(:show_id)
        pending_shows = shows.where.not(id: submitted_show_ids)

        # Generate personalized message by substituting their specific shows list
        personalized_message = generate_personalized_message(pending_shows, message_template)

        Manage::AvailabilityMailer.request_availability(person, @production, personalized_message).deliver_later
      end
    end

    redirect_to manage_production_availability_index_path(@production), notice: "Availability request sent to #{recipients.count} #{'person'.pluralize(recipients.count)}"
  end

  def update_show_availability
    @show = @production.shows.find(params[:id])

    # Update availabilities for each person and group
    params.each do |key, value|
      # Match pattern: availability_Person_123 or availability_Group_456
      if key.match?(/^availability_(Person|Group)_(\d+)$/)
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
