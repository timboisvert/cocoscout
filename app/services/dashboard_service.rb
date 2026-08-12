# frozen_string_literal: true

class DashboardService
  def initialize(production, batch: nil)
    @production = production
    @batch = batch
  end

  def generate
    Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
      build_payload
    end
  end

  # Dashboard data for many productions at once — the org home page. Computing
  # each production's cache key individually costs ~6 aggregate queries per
  # production on EVERY request (cache hit or not), which is what made /manage
  # crawl. Here the timestamps behind the keys come from 6 grouped queries
  # total, and all keys are read in one fetch_multi round-trip. Keys are
  # byte-identical to the single-production path, so the two stay interchangeable.
  # Returns { production_id => payload }.
  def self.generate_all(productions)
    productions = productions.to_a
    return {} if productions.empty?

    ids = productions.map(&:id)

    show_max = Show.where(production_id: ids).reorder(nil).group(:production_id).maximum(:updated_at)
    request_max = AuditionRequest.joins(:audition_cycle)
                                 .where(audition_cycles: { production_id: ids, active: true })
                                 .reorder(nil).group("audition_cycles.production_id").maximum(:updated_at)
    vacancy_max = RoleVacancy.joins(:show).where(shows: { production_id: ids })
                             .reorder(nil).group("shows.production_id").maximum(:updated_at)
    assignment_max = ShowPersonRoleAssignment.joins(:show).where(shows: { production_id: ids })
                                             .reorder(nil).group("shows.production_id").maximum(:updated_at)
    role_max = Role.where(production_id: ids, show_id: nil).reorder(nil).group(:production_id).maximum(:updated_at)
    form_max = SignUpForm.where(production_id: ids).reorder(nil).group(:production_id).maximum(:updated_at)

    production_by_key = productions.to_h do |production|
      key = [
        "dashboard_v5",
        production.id,
        production.updated_at.to_i,
        show_max[production.id]&.to_i,
        request_max[production.id]&.to_i,
        vacancy_max[production.id]&.to_i,
        assignment_max[production.id]&.to_i,
        role_max[production.id]&.to_i,
        form_max[production.id]&.to_i
      ]
      [ key, production ]
    end

    payloads = Rails.cache.read_multi(*production_by_key.keys)

    # Build the misses together: one Batch runs the grouped queries every
    # per-production payload would otherwise run individually.
    missing = production_by_key.reject { |key, _| payloads.key?(key) }
    if missing.any?
      batch = Batch.new(missing.values)
      built = missing.to_h { |key, production| [ key, new(production, batch: batch).send(:build_payload) ] }
      Rails.cache.write_multi(built, expires_in: 5.minutes)
      payloads.merge!(built)
    end

    production_by_key.to_h { |key, production| [ production.id, payloads[key] ] }
  end

  # Shared data source for generate_all cache misses: every per-production
  # query the payload methods run, executed once for the whole production set.
  # Accessors mirror the shapes the single-production queries return.
  class Batch
    def initialize(productions)
      @now = Time.current
      ids = productions.map(&:id)

      ActiveRecord::Associations::Preloader.new(
        records: productions,
        associations: [ :organization, { audition_cycles: :audition_requests },
                        :talent_pools, { talent_pool_shares: :talent_pool } ]
      ).call

      window_shows = Show.where(production_id: ids)
                         .where("date_and_time >= ? AND date_and_time <= ?", @now, 6.weeks.from_now)
                         .includes(:location, :custom_roles, :show_person_role_assignments, :show_availabilities)
                         .order(date_and_time: :asc)
                         .to_a
      @shows_by_production = window_shows.group_by(&:production_id)

      @roles_by_production = Role.production_roles.where(production_id: ids).group_by(&:production_id)

      pool_ids = productions.flat_map(&:effective_talent_pool_ids).uniq
      @person_ids_by_pool = TalentPoolMembership
                            .where(talent_pool_id: pool_ids, member_type: "Person")
                            .pluck(:talent_pool_id, :member_id)
                            .group_by(&:first)
                            .transform_values { |rows| rows.map(&:last) }

      @vacancies_by_production = RoleVacancy.open
                                            .joins(:show)
                                            .where(shows: { production_id: ids })
                                            .where("shows.date_and_time >= ?", @now)
                                            .includes(:role, :show, :affected_shows, invitations: :person)
                                            .to_a
                                            .group_by { |v| v.show.production_id }

      @forms_by_production = SignUpForm
                             .where(production_id: ids, active: true, archived_at: nil)
                             .includes({ sign_up_slots: :sign_up_registrations },
                                       { sign_up_form_instances: [ :show, { sign_up_slots: :sign_up_registrations } ] })
                             .order(created_at: :desc)
                             .group_by(&:production_id)
    end

    def upcoming_shows(production_id)
      (@shows_by_production[production_id] || []).first(5)
    end

    # availability_summary's window is exclusive of "now" where the shared
    # fetch is inclusive — re-apply the boundary for parity.
    def availability_shows(production_id)
      (@shows_by_production[production_id] || []).select { |s| s.date_and_time > @now }
    end

    def production_roles(production_id)
      @roles_by_production[production_id] || []
    end

    def pool_person_ids(production)
      production.effective_talent_pool_ids
                .flat_map { |pool_id| @person_ids_by_pool[pool_id] || [] }
                .uniq
    end

    def vacancies(production_id)
      (@vacancies_by_production[production_id] || []).sort_by { |v| v.show.date_and_time }
    end

    def sign_up_forms(production_id)
      @forms_by_production[production_id] || []
    end
  end

  private

  def build_payload
    {
      open_calls: open_calls_summary,
      upcoming_shows: upcoming_shows,
      availability_summary: availability_summary,
      open_vacancies: open_vacancies,
      sign_up_forms: sign_up_forms_summary
    }
  end

  def cache_key
    # Cache key includes production ID and relevant timestamps. Must stay in
    # lockstep with the bulk key construction in .generate_all above.
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

  # People in the production's effective talent pool — from the batch when
  # generate_all is driving, one query otherwise. Memoized because both
  # upcoming_shows and availability_summary need it.
  def cast_person_ids
    @cast_person_ids ||= if @batch
      @batch.pool_person_ids(@production)
    else
      Person.joins(:talent_pool_memberships)
            .where(talent_pool_memberships: { talent_pool_id: @production.effective_talent_pool_ids })
            .distinct
            .pluck(:id)
    end
  end

  # A show's castable roles without the per-show production.roles query the
  # unbatched available_roles path would run.
  def roles_for(show)
    if show.use_custom_roles?
      show.custom_roles.to_a
    elsif @batch
      @batch.production_roles(show.production_id)
    else
      show.available_roles.to_a
    end
  end

  def open_calls_summary
    call = @production.audition_cycle
    return { total_open: 0, with_auditionees: [] } if call.blank?

    is_open = call.opens_at <= Time.current && (call.closes_at.nil? || call.closes_at >= Time.current)
    return { total_open: 0, with_auditionees: [] } unless is_open

    # Only count active (non-archived) audition requests
    auditionee_count = call.active_audition_requests_count

    {
      total_open: 1,
      with_auditionees: [ {
        call: call,
        auditionee_count: auditionee_count
      } ]
    }
  end

  def upcoming_shows
    all_cast_person_ids = cast_person_ids
    total_cast_count = all_cast_person_ids.size

    shows = if @batch
      @batch.upcoming_shows(@production.id)
    else
      # Eager load location, assignments, and availabilities in a single query
      @production.shows
                 .where("date_and_time >= ? AND date_and_time <= ?", Time.current, 6.weeks.from_now)
                 .includes(:location, :show_person_role_assignments, :show_availabilities)
                 .order(date_and_time: :asc)
                 .limit(5)
    end

    shows.map do |show|
      # Use .size on already-loaded associations to avoid COUNT queries
      assignments_count = show.show_person_role_assignments.size
      # Calculate total slots (sum of quantities for multi-person roles)
      roles = roles_for(show)
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
    upcoming_shows = if @batch
      @batch.availability_shows(@production.id)
    else
      # Eager load shows with availabilities in a single query
      @production.shows
                 .where("date_and_time > ? AND date_and_time <= ?", Time.current, 6.weeks.from_now)
                 .includes(:show_availabilities)
                 .order(date_and_time: :asc)
    end

    all_cast_person_ids = cast_person_ids
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
    vacancies = if @batch
      @batch.vacancies(@production.id)
    else
      RoleVacancy.open
                 .joins(:show)
                 .where(shows: { production_id: @production.id })
                 .where("shows.date_and_time >= ?", Time.current)
                 .includes(:role, :show, :affected_shows, invitations: :person)
                 .order("shows.date_and_time ASC")
    end

    vacancies.map do |vacancy|
                 affected = vacancy.affected_shows.sort_by(&:date_and_time)
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
    forms = if @batch
      @batch.sign_up_forms(@production.id)
    else
      @production.sign_up_forms.where(active: true, archived_at: nil).order(created_at: :desc)
                 .includes({ sign_up_slots: :sign_up_registrations },
                           { sign_up_form_instances: [ :show, { sign_up_slots: :sign_up_registrations } ] })
    end

    forms.map do |form|
      # Get the current/next instance for repeated forms (instances are
      # preloaded above, so both branches work in memory)
      instance = if form.repeated?
        form.sign_up_form_instances
            .select { |i| i.show && i.show.date_and_time > Time.current }
            .min_by { |i| [ i.show.date_and_time, i.id ] }
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
