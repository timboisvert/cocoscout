class My::AvailabilityController < ApplicationController
  def index
    @filter = (params[:filter] || session[:availability_filter] || "no_response")
    session[:availability_filter] = @filter

    @productions = Production.joins(casts: [ :casts_people ]).joins(:shows).where(casts_people: { person_id: Current.user.person.id }).distinct

    # Get all upcoming non-canceled shows
    @all_shows = Show.joins(production: { casts: [ :casts_people ] })
      .where(casts_people: { person_id: Current.user.person.id })
      .where.not(canceled: true)
      .where("date_and_time > ?", Time.current)
      .order(:date_and_time)
      .distinct

    # Get shows with no response
    availability_ids = ShowAvailability.where(person: Current.user.person).pluck(:show_id)
    @no_response_shows = @all_shows.where.not(id: availability_ids)

    # Group shows by production for the by_production view
    @shows_by_production = {}
    @productions.each do |production|
      @shows_by_production[production] = production.shows
        .where.not(canceled: true)
        .where("date_and_time > ?", Time.current)
        .order(:date_and_time)
    end

    @availabilities = ShowAvailability.where(person: Current.user.person).index_by(&:show_id)
  end

  def update
    @show = Show.find(params[:show_id])
    @availability = ShowAvailability.find_or_initialize_by(person: Current.user.person, show: @show)
    @availability.status = params[:status]
    if @availability.save
      render json: { status: @availability.status }
    else
      render json: { error: @availability.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end
end
