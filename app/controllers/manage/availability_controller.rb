class Manage::AvailabilityController < Manage::ManageController
  before_action :set_production

  def index
    # Get all future shows for this production, ordered by date
    @shows = @production.shows.where(canceled: false).where("date_and_time >= ?", Time.current).order(:date_and_time)

    # Get all cast members (people and groups) for this production
    @people = @production.talent_pools.flat_map(&:people).uniq.sort_by(&:name)
    @groups = @production.talent_pools.flat_map(&:groups).uniq.sort_by(&:name)
    @cast_members = (@people + @groups).sort_by(&:name)

    # Build a hash of availabilities: { "Person_1" => { show_id => show_availability }, "Group_2" => ... }
    @availabilities = {}
    @cast_members.each do |member|
      key = "#{member.class.name}_#{member.id}"
      @availabilities[key] = {}
      member.show_availabilities.where(show: @shows).each do |availability|
        @availabilities[key][availability.show_id] = availability
      end
    end
  end

  def show
    # Get the specific show
    @show = @production.shows.find(params[:id])

    # Get all cast members (people and groups) for this production
    @people = @production.talent_pools.flat_map(&:people).uniq.sort_by(&:name)
    @groups = @production.talent_pools.flat_map(&:groups).uniq.sort_by(&:name)
    @cast_members = (@people + @groups).sort_by(&:name)

    # Build a hash of availabilities for this show
    @availabilities = {}
    @cast_members.each do |member|
      key = "#{member.class.name}_#{member.id}"
      @availabilities[key] = member.show_availabilities.find_by(show: @show)
    end

    # Track edit mode
    @edit_mode = params[:edit] == "true"
  end

  def request_availability
    # Get all future shows for this production
    @shows = @production.shows.where(canceled: false).where("date_and_time >= ?", Time.current).order(:date_and_time)

    # Get all talent pools for this production
    @talent_pools = @production.talent_pools.order(:name)

    # Get all cast members
    @cast_members = @production.talent_pools.flat_map(&:people).uniq.sort_by(&:name)

    # Determine which cast members are up to date (have submitted availability for all future shows)
    @up_to_date_person_ids = @cast_members.select do |person|
      submitted_show_ids = person.show_availabilities.where(show: @shows).pluck(:show_id)
      submitted_show_ids.sort == @shows.pluck(:id).sort
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
