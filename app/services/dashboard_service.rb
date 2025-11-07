class DashboardService
  def initialize(production)
    @production = production
  end

  def generate
    {
      open_calls: open_calls_summary,
      upcoming_shows: upcoming_shows,
      availability_summary: availability_summary
    }
  end

  private

  def open_calls_summary
    call = @production.call_to_audition
    return { total_open: 0, with_auditionees: [] } if call.blank?

    is_open = call.opens_at <= Time.current && call.closes_at >= Time.current
    return { total_open: 0, with_auditionees: [] } unless is_open

    {
      total_open: 1,
      with_auditionees: [ {
        call: call,
        auditionee_count: call.audition_requests.count
      } ]
    }
  end

  def upcoming_shows
    @production.shows
      .where("date_and_time >= ? AND date_and_time <= ?", Date.today, 6.weeks.from_now)
      .order(date_and_time: :asc)
      .limit(5)
      .map do |show|
        uncast_count = @production.roles.count - show.show_person_role_assignments.count
        days_until = (show.date_and_time.to_date - Date.today).to_i

        days_label = case days_until
        when 0 then "today"
        when 1 then "tomorrow"
        else "#{days_until} days from now"
        end

        {
          show: show,
          uncast_count: uncast_count,
          days_until: days_label,
          cast_percentage: ((show.show_person_role_assignments.count.to_f / @production.roles.count) * 100).round
        }
      end
  end

  def availability_summary
    upcoming_shows = @production.shows
      .where("date_and_time > ? AND date_and_time <= ?", Time.current, 6.weeks.from_now)
      .order(date_and_time: :asc)

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
end
