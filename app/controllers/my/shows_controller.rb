class My::ShowsController < ApplicationController
  def index
    # Get all productions where user is a cast member
    @productions = Production.joins(talent_pools: :people)
                             .where(people: { id: Current.user.person.id })
                             .distinct
                             .order(:name)

    # Handle filter parameters
    @filter = params[:filter] || "all"
    @event_type_filter = params[:event_type]

    # Get all upcoming shows for user's productions
    @shows = Show.joins(production: { talent_pools: :people })
                .where(people: { id: Current.user.person.id })
                .where("date_and_time >= ?", Time.current)
                .select("shows.*")
                .distinct

    # Apply event type filter if specified
    if @event_type_filter.present?
      @shows = @shows.where(event_type: @event_type_filter)
    end

    # Order and load shows to avoid pluck with distinct/order issue
    @shows = @shows.order(:date_and_time).to_a

    # Get assignments for these shows
    show_ids = @shows.map(&:id)
    assignments = ShowPersonRoleAssignment.where(show_id: show_ids, person_id: Current.user.person.id)
    @assignments_by_show = assignments.index_by(&:show_id)
  end

  def show
    @show = Show.joins(production: { talent_pools: :people })
               .where(people: { id: Current.user.person.id })
               .find(params[:id])
    @production = @show.production
    @show_person_role_assignments = @show.show_person_role_assignments.includes(:assignable, :role)

    # Get my assignment for this show (direct person assignment)
    @my_assignment = @show_person_role_assignments.find { |a| a.assignable_type == "Person" && a.assignable_id == Current.user.person.id }
  end

  def calendar
    @event_type_filter = params[:event_type] || "all"

    # Get all upcoming non-canceled shows
    @shows = Show.joins(production: { talent_pools: :people })
                .where(people: { id: Current.user.person.id })
                .where("date_and_time >= ?", Time.current)
                .where(canceled: false)
                .select("shows.*")
                .distinct

    # Apply event type filter
    unless @event_type_filter == "all"
      @shows = @shows.where(event_type: @event_type_filter)
    end

    # Order and load shows to avoid pluck with distinct/order issue
    @shows = @shows.order(:date_and_time).to_a

    # Group shows by month
    @shows_by_month = @shows.group_by { |show| show.date_and_time.beginning_of_month }

    # Get assignments for these shows
    show_ids = @shows.map(&:id)
    assignments = ShowPersonRoleAssignment.where(show_id: show_ids, person_id: Current.user.person.id)
    @assignments_by_show = assignments.index_by(&:show_id)
  end
end
