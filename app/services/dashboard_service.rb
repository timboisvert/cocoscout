class DashboardService
  def initialize(production)
    @production = production
  end

  def generate
    {
      shows_summary: shows_summary,
      uncast_roles: uncast_roles_summary,
      open_calls: open_calls_summary,
      recent_auditions: recent_auditions_summary,
      cast_summary: cast_summary,
      roles_summary: roles_summary,
      people_summary: people_summary,
      upcoming_shows: upcoming_shows,
      availability_summary: availability_summary,
      audition_requests_summary: audition_requests_summary
    }
  end

  private

  def shows_summary
    {
      total: @production.shows.count,
      fully_cast: @production.shows.select { |s| s.show_person_role_assignments.count == @production.roles.count }.count,
      partially_cast: 0,
      uncast_count: 0
    }.tap do |summary|
      summary[:partially_cast] = summary[:total] - summary[:fully_cast] - summary[:uncast_count]
    end
  end

  def uncast_roles_summary
    uncast_assignments = @production.shows.flat_map do |show|
      @production.roles.select do |role|
        !show.show_person_role_assignments.exists?(role_id: role.id)
      end
    end

    {
      total_uncast: uncast_assignments.count,
      shows_with_uncast: @production.shows.select { |s| s.show_person_role_assignments.count < @production.roles.count }.count,
      by_show: @production.shows.map do |show|
        uncast_for_show = @production.roles.select do |role|
          !show.show_person_role_assignments.exists?(role_id: role.id)
        end
        {
          show: show,
          uncast_roles: uncast_for_show,
          count: uncast_for_show.count
        }
      end.select { |item| item[:count] > 0 }
    }
  end

  def open_calls_summary
    calls = @production.call_to_auditions
      .where("opens_at <= ? AND closes_at >= ?", Time.current, Time.current)
      .includes(:audition_requests)
    {
      total_open: calls.count,
      with_auditionees: calls.map do |call|
        {
          call: call,
          auditionee_count: call.audition_requests.count
        }
      end
    }
  end

  def recent_auditions_summary
    audition_requests = @production.audition_requests
      .order(created_at: :desc)
      .limit(10)
      .includes(:call_to_audition)

    {
      recent_count: audition_requests.count,
      pending_count: audition_requests.where(status: "pending").count,
      approved_count: audition_requests.where(status: "approved").count,
      recent_auditions: audition_requests
    }
  end

  def cast_summary
    {
      total_casts: @production.casts.count,
      casts: @production.casts.map do |cast|
        {
          cast: cast,
          people_count: cast.people.count
        }
      end
    }
  end

  def roles_summary
    {
      total_roles: @production.roles.count
    }
  end

  def people_summary
    all_people = @production.shows.flat_map(&:people).uniq
    {
      total_people_cast: all_people.count,
      total_in_system: @production.casts.flat_map(&:people).uniq.count
    }
  end

  def upcoming_shows
    @production.shows
      .where("date_and_time >= ?", Date.today)
      .order(date_and_time: :asc)
      .limit(5)
      .map do |show|
        uncast_count = @production.roles.count - show.show_person_role_assignments.count
        {
          show: show,
          uncast_count: uncast_count,
          days_until: (show.date_and_time.to_date - Date.today).to_i,
          cast_percentage: ((show.show_person_role_assignments.count.to_f / @production.roles.count) * 100).round
        }
      end
  end

  def shows_needing_attention
    @production.shows.select do |show|
      uncast_count = @production.roles.count - show.show_person_role_assignments.count
      uncast_count > 0 && show.date_and_time && show.date_and_time > Time.current && show.date_and_time.to_date <= 30.days.from_now
    end.sort_by { |s| s.date_and_time || Time.current }
  end

  def availability_summary
    upcoming_shows = @production.shows.where('date_and_time > ?', Time.current).order(date_and_time: :asc)
    
    # Get all people in the production's casts
    all_cast_people = @production.casts.flat_map(&:people).uniq
    
    shows_with_availability = upcoming_shows.map do |show|
      # For each show, check which cast people have an availability record
      people_with_availability = show.show_availabilities.where(person_id: all_cast_people.pluck(:id)).count
      people_without_availability = all_cast_people.count - people_with_availability
      
      {
        show: show,
        total_cast_people: all_cast_people.count,
        with_availability: people_with_availability,
        without_availability: people_without_availability,
        percentage_responded: all_cast_people.count > 0 ? ((people_with_availability.to_f / all_cast_people.count) * 100).round : 0
      }
    end
    
    {
      shows_with_availability: shows_with_availability,
      shows_needing_responses: shows_with_availability.select { |s| s[:without_availability] > 0 },
      total_shows: shows_with_availability.count,
      fully_responded: shows_with_availability.select { |s| s[:without_availability] == 0 }.count
    }
  end

  def audition_requests_summary
    requests = @production.audition_requests
    {
      total: requests.count,
      pending: requests.where(status: "pending").count,
      approved: requests.where(status: "approved").count,
      rejected: requests.where(status: "rejected").count
    }
  end
end
