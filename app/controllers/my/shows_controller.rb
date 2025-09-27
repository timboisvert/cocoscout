class My::ShowsController < ApplicationController
  def index
    @productions = Production.joins(casts: [ :casts_people ]).where(casts_people: { person_id: Current.user.person.id }).distinct
  end

  def show
    @production = Production.find(params[:id])
    @shows = @production.shows.order(date_and_time: :asc)

    # Get my assignments, then relate them to each show
    show_person_role_assignments = @production.show_person_role_assignments.where(show_id: @shows.pluck(:id), person_id: Current.user.person.id)
    @assignments_by_show = @shows.index_with do |show|
      show_person_role_assignments.find { |assignment| assignment.show_id == show.id }
    end
  end
end
