class Manage::AvailabilityController < Manage::ManageController
  before_action :set_production

  def index
    # Get all shows for this production, ordered by date
    @shows = @production.shows.where(canceled: false).order(:date_and_time)

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

  private

  def set_production
    @production = Current.production_company.productions.find(params[:production_id])
  end
end
