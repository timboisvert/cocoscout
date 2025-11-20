class Manage::CastingController < Manage::ManageController
  before_action :set_production
  before_action :check_production_access

  def index
    @upcoming_shows = @production.shows
      .where("date_and_time >= ?", Time.current)
      .includes(show_person_role_assignments: [ :person, :role ])
      .order(:date_and_time)
      .limit(10)
  end

  private
    def set_production
      @production = Current.organization.productions.find(params.require(:production_id))
    end
end
