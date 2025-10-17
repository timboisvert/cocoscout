class My::AvailabilitiesController < ApplicationController
  def index
    @productions = Production.joins(casts: [ :casts_people ]).joins(:shows).where(casts_people: { person_id: Current.user.person.id }).distinct
    @shows_by_production = {}
    @productions.each do |production|
      @shows_by_production[production] = production.shows.where.not(canceled: true).order(:date_and_time)
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
