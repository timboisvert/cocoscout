# frozen_string_literal: true

class DashboardService
  def initialize(production)
    @production = production
  end

  def generate
    Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
      {
        open_calls: open_calls_summary,
        upcoming_shows: upcoming_shows,
        availability_summary: availability_summary,
        open_vacancies: open_vacancies,
        sign_up_forms: sign_up_forms_summary
      }
    end
  end

  def self.invalidate(production)
    Rails.cache.delete([ "dashboard_v5", production.id ])
  end

  private

  def cache_key
    # Cache key includes production ID and relevant timestamps
    max_show_updated = @production.shows.maximum(:updated_at)
    max_request_updated = @production.audition_cycle&.audition_requests&.maximum(:updated_at)
    max_vacancy_updated = RoleVacancy.joins(:show).where(shows: { production_id: @production.id }).maximum(:updated_at)
    max_assignment_updated = ShowPersonRoleAssignment.joins(:show).where(shows: { production_id: @production.id }).maximum(:updated_at)
    max_role_updated = @production.roles.maximum(:updated_at)
    max_sign_up_form_updated = @production.sign_up_forms.maximum(:updated_at)
    [
      "dashboard_v5",
      @production.id,
      @production.updated_at.to_i,
      max_show_updated&.to_i,
      max_request_updated&.to_i,
      max_vacancy_updated&.to_i,
      max_assignment_updated&.to_i,
      max_role_updated&.to_i,
      max_sign_up_form_updated&.to_i
    ]
  end

  def open_calls_summary
    call = @production.audition_cycle
    return { total_open: 0, with_auditionees: [] } if call.blank?

    is_open = call.opens_at <= Time.current && (call.closes_at.nil? || call.closes_at >= Time.current)
    return { total_open: 0, with_auditionees: [] } unless is_open

    # Use size instead of count to avoid extra query if already loaded
    auditionee_count = call.audition_requests.size

    {
      total_open: 1,
      with_auditionees: [ {
        call: call,
        auditionee_count: auditionee_count
      } ]
    }
  end

  def upcoming_shows
    # Get all people in the production's effective talent pool (may be shared) in a single query
    all_cast_person_ids = Person
                          .joins(:talent_pool_memberships)
                          .where(talent_pool_memberships: { talent_pool_id: @production.effective_talent_pool_ids })
                          .distinct
                          .pluck(:id)

    total_cast_count = all_cast_person_ids.size

    # Eager load location, assignments, and availabilities in a single query
    shows = @production.shows
                       .where("date_and_time >= ? AND date_and_time <= ?", Time.current, 6.weeks.from_now)
                       .includes(:location, :show_person_role_assignments, :show_availabilities)
                       .order(date_and_time: :asc)
                       .limit(5)

    shows.map do |show|
      # Use .size on already-loaded associations to avoid COUNT queries
      assignments_count = show.show_person_role_assignments.size
      # Calculate total slots (sum of quantities for multi-person roles)
      roles = show.available_roles.to_a
      roles_count = roles.sum { |r| r.quantity || 1 }
      uncast_count = roles_count - assignments_count
      days_until = (show.date_and_time.to_date - Date.today).to_i

      days_label = case days_until
      when 0 then "today"
      when 1 then "tomorrow"
      else "#{days_until} days from now"
      end

      cast_percentage = if roles_count.positive?
                          ((assignments_count.to_f / roles_count) * 100).round
      else
                          100 # If there are no roles, consider it 100% cast
      end

      # Availability data
      people_with_availability = show.show_availabilities.count do |avail|
        avail.available_entity_type == "Person" && all_cast_person_ids.include?(avail.available_entity_id)
      end
      availability_percentage = total_cast_count.positive? ? ((people_with_availability.to_f / total_cast_count) * 100).round : 0

      {
        show: show,
        uncast_count: uncast_count,
        days_until: days_label,
        cast_count: assignments_count,
        roles_count: roles_count,
        cast_percentage: cast_percentage,
        total_cast_count: total_cast_count,
        availability_count: people_with_availability,
        availability_percentage: availability_percentage
      }
    end
  end

  def availability_summary
    # Eager load shows with availabilities in a single query
    upcoming_shows = @production.shows
                                .where("date_and_time > ? AND date_and_time <= ?", Time.current, 6.weeks.from_now)
                                .includes(:show_availabilities)
                                .order(date_and_time: :asc)

    # Get all people in the production's effective talent pool (may be shared) in a single query
    # Use joins instead of flat_map to avoid N+1
    all_cast_person_ids = Person
                          .joins(:talent_pool_memberships)
                          .where(talent_pool_memberships: { talent_pool_id: @production.effective_talent_pool_ids })
                          .distinct
                          .pluck(:id)

    total_cast_count = all_cast_person_ids.size

    shows_with_availability = upcoming_shows.map do |show|
      # Use already-loaded show_availabilities and filter in memory
      people_with_availability = show.show_availabilities.count do |avail|
        avail.available_entity_type == "Person" && all_cast_person_ids.include?(avail.available_entity_id)
      end
      people_without_availability = total_cast_count - people_with_availability

      {
        show: show,
        total_cast_people: total_cast_count,
        with_availability: people_with_availability,
        without_availability: people_without_availability,
        percentage_responded: total_cast_count.positive? ? ((people_with_availability.to_f / total_cast_count) * 100).round : 0
      }
    end

    {
      shows_with_availability: shows_with_availability,
      shows_needing_responses: shows_with_availability.select { |s| s[:without_availability].positive? },
      total_shows: shows_with_availability.count,
      fully_responded: shows_with_availability.select { |s| s[:without_availability].zero? }.count
    }
  end

  def open_vacancies
    RoleVacancy.open
               .joins(:show)
               .where(shows: { production_id: @production.id })
               .where("shows.date_and_time >= ?", Time.current)
               .includes(:role, :show, :affected_shows, invitations: :person)
               .order("shows.date_and_time ASC")
               .map do |vacancy|
                 affected = vacancy.affected_shows.order(:date_and_time).to_a
                 # Check if the show itself is linked, not just whether affected_shows has entries
                 is_linked = vacancy.show.linked?
                 {
                   vacancy: vacancy,
                   show: vacancy.show,
                   role: vacancy.role,
                   invitations_count: vacancy.invitations.size,
                   pending_invitations_count: vacancy.invitations.count(&:pending?),
                   affected_shows: affected,
                   is_linked: is_linked
                 }
               end
  end

  def sign_up_forms_summary
    forms = @production.sign_up_forms.where(active: true, archived_at: nil).order(created_at: :desc)

    forms.map do |form|
      # Get the current/next instance for repeated forms
      instance = if form.repeated?
        form.sign_up_form_instances
            .joins(:show)
            .where("shows.date_and_time > ?", Time.current)
            .order("shows.date_and_time ASC, sign_up_form_instances.id ASC")
            .first
      else
        form.sign_up_form_instances.first
      end

      next nil unless instance

      # Get full status from the status service
      form_status = form.current_status

      {
        form: form,
        instance: instance,
        form_status: form_status
      }
    end.compact
  end
end
