class My::ShowsController < ApplicationController
  def index
    @productions = Production.joins(casts: [ :casts_people ]).joins(:shows).where(casts_people: { person_id: Current.user.person.id }).distinct
  end

  def production
    @production = Production.find(params[:production_id])
    @shows = @production.shows.where("date_and_time > ?", Time.current).order(date_and_time: :asc)

    # Get my assignments, then relate them to each show
    show_person_role_assignments = @production.show_person_role_assignments.where(show_id: @shows.pluck(:id), person_id: Current.user.person.id)
    @assignments_by_show = @shows.index_with do |show|
      show_person_role_assignments.find { |assignment| assignment.show_id == show.id }
    end
  end

  def show
    @production = Production.joins(casts: [ :casts_people ]).where(casts_people: { person_id: Current.user.person.id }).find(params[:production_id])
    @show = @production.shows.find(params[:show_id])
    @show_person_role_assignments = @show.show_person_role_assignments
  end
end
