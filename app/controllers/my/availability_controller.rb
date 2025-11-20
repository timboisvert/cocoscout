class My::AvailabilityController < ApplicationController
  def index
    @filter = (params[:filter] || session[:availability_filter] || "no_response")
    session[:availability_filter] = @filter

    @productions = Production.joins(talent_pools: :people).joins(:shows).where(people: { id: Current.user.person.id }).distinct

    # Get all upcoming non-canceled shows
    @all_shows = Show.joins(production: { talent_pools: :people })
      .where(people: { id: Current.user.person.id })
      .where.not(canceled: true)
      .where("date_and_time > ?", Time.current)
      .order(:date_and_time)
      .distinct

    # Get shows with no response
    availability_ids = ShowAvailability.where(available_entity: Current.user.person).pluck(:show_id)
    @no_response_shows = @all_shows.where.not(id: availability_ids)

    # Group shows by production for the by_production view
    @shows_by_production = {}
    @productions.each do |production|
      @shows_by_production[production] = production.shows
        .where.not(canceled: true)
        .where("date_and_time > ?", Time.current)
        .order(:date_and_time)
    end

    @availabilities = ShowAvailability.where(available_entity: Current.user.person).index_by(&:show_id)
  end

  def calendar
    @event_filter = params[:event_type] || "all"

    # Get all upcoming non-canceled shows
    @shows = Show.joins(production: { talent_pools: :people })
      .where(people: { id: Current.user.person.id })
      .where.not(canceled: true)
      .where("date_and_time > ?", Time.current)
      .order(:date_and_time)
      .distinct

    # Apply event type filter
    unless @event_filter == "all"
      @shows = @shows.where(event_type: @event_filter)
    end

    # Group shows by month
    @shows_by_month = @shows.group_by { |show| show.date_and_time.beginning_of_month }

    @availabilities = ShowAvailability.where(available_entity: Current.user.person).index_by(&:show_id)
  end

  def update
    @show = Show.find(params[:show_id])
    @availability = ShowAvailability.find_or_initialize_by(available_entity: Current.user.person, show: @show)
    @availability.status = params[:status]
    if @availability.save
      render json: { status: @availability.status }
    else
      render json: { error: @availability.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end
end
