class Manage::AvailabilityController < Manage::ManageController
  before_action :set_production

  def index
    # Get all future shows for this production, ordered by date
    @shows = @production.shows.where(canceled: false).where("date_and_time >= ?", Time.current).order(:date_and_time)

    # Get all cast members for this production
    @cast_members = @production.casts.flat_map(&:people).uniq.sort_by(&:name)

    # Build a hash of availabilities: { person_id => { show_id => show_availability } }
    @availabilities = {}
    @cast_members.each do |person|
      @availabilities[person.id] = {}
      person.show_availabilities.where(show: @shows).each do |availability|
        @availabilities[person.id][availability.show_id] = availability
      end
    end
  end

  def request_availability
    # Get all future shows for this production
    @shows = @production.shows.where(canceled: false).where("date_and_time >= ?", Time.current).order(:date_and_time)

    # Get all casts for this production
    @casts = @production.casts.order(:name)

    # Get all cast members
    @cast_members = @production.casts.flat_map(&:people).uniq.sort_by(&:name)

    # Determine which cast members are up to date (have submitted availability for all future shows)
    @up_to_date_person_ids = @cast_members.select do |person|
      submitted_show_ids = person.show_availabilities.where(show: @shows).pluck(:show_id)
      submitted_show_ids.sort == @shows.pluck(:id).sort
    end.map(&:id)

    # Split cast members into those needing updates and those up to date
    @cast_members_needing_update = @cast_members.reject { |p| @up_to_date_person_ids.include?(p.id) }
    @cast_members_up_to_date = @cast_members.select { |p| @up_to_date_person_ids.include?(p.id) }

    # Generate default message
    @default_message = generate_default_message
  end

  def handle_request_availability
    recipient_type = params[:recipient_type]
    cast_id = params[:cast_id]
    person_ids = params[:person_ids] || []
    message_template = params[:message]

    # Get future shows to determine who needs updates
    shows = @production.shows.where(canceled: false).where("date_and_time >= ?", Time.current)

    # Determine recipients based on recipient_type
    all_recipients = if recipient_type == "all"
      @production.casts.flat_map(&:people).uniq
    elsif recipient_type == "cast"
      Cast.find(cast_id).people
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

  private

  def set_production
    @production = Current.production_company.productions.find(params.expect(:production_id))
  end

  def generate_default_message
    shows_list = @shows.map do |show|
      "• #{show.date_and_time.strftime('%A, %B %d, %Y at %-l:%M %p')} - #{show.event_type.titleize}"
    end.join("\n")

    <<~MESSAGE
      Please submit your availability for the following upcoming #{@production.name} shows & events:

      #{shows_list}

      You can update your availability by visiting:
      <a href="#{my_availability_url(host: request.host_with_port, protocol: request.protocol.chomp('://'))}">#{my_availability_url(host: request.host_with_port, protocol: request.protocol.chomp('://'))}</a>
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
