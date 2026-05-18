# frozen_string_literal: true

# Aggregates a chronological feed of a Person's activity across the system.
#
# Pagination strategy: each source query pushes its `< before` cursor filter
# and `LIMIT n+1` down to SQL, so we never load entire tables into memory.
# We then merge the per-source results and pick the global top N. Worst case
# we hold (N+1) × (number of sources) Ruby objects per page, regardless of
# how much history a person has.
class PersonHistoryFeed
  Entry = Struct.new(
    :occurred_at,
    :kind,
    :title,
    :subtitle,
    :details,
    :url,
    :answers,
    keyword_init: true
  )

  def initialize(person)
    @person = person
  end

  def most_recent
    page(limit: 1).first
  end

  # Returns up to `limit` entries strictly older than `before` (a Time or nil).
  def page(limit: 20, before: nil)
    return [] if @person.nil?

    # Ask each source for one more than we need so the controller can detect
    # whether more pages exist after merging.
    per_source_limit = limit + 1
    all = []
    all.concat(audition_request_entries(per_source_limit, before))
    all.concat(audition_entries(per_source_limit, before))
    all.concat(audition_acceptance_entries(per_source_limit, before))
    all.concat(audition_session_availability_entries(per_source_limit, before))
    all.concat(sign_up_entries(per_source_limit, before))
    all.concat(course_entries(per_source_limit, before))
    all.concat(vacancy_created_entries(per_source_limit, before))
    all.concat(vacancy_filled_entries(per_source_limit, before))
    all.concat(cast_assignment_entries(per_source_limit, before))

    all.sort_by { |e| -e.occurred_at.to_f }.first(limit)
  end

  private

  # Allowed sort columns. Keeping these as a constant means the column name in
  # SQL is never derived from user input — Brakeman's SQL-injection check
  # passes without an ignore entry, and a typo'd call raises loudly instead
  # of silently interpolating something arbitrary.
  ALLOWED_CURSOR_COLUMNS = [
    "audition_requests.created_at",
    "audition_sessions.start_at",
    "sign_up_registrations.registered_at",
    "course_registrations.registered_at",
    "auditions.accepted_at",
    "audition_session_availabilities.updated_at",
    "COALESCE(role_vacancies.vacated_at, role_vacancies.created_at)",
    "role_vacancies.filled_at",
    "shows.casting_finalized_at"
  ].freeze

  def scope_with_cursor(relation, column, before, limit)
    unless ALLOWED_CURSOR_COLUMNS.include?(column)
      raise ArgumentError, "Unknown cursor column for PersonHistoryFeed: #{column.inspect}"
    end

    relation = relation.where(Arel.sql("#{column} < ?"), before) if before
    relation.order(Arel.sql("#{column} DESC")).limit(limit)
  end

  def audition_request_entries(limit, before)
    scope = AuditionRequest
      .where(requestable_type: "Person", requestable_id: @person.id)
    scope = scope_with_cursor(scope, "audition_requests.created_at", before, limit)
      .includes(audition_cycle: :production, answers: :question)

    scope.map do |req|
      production = req.audition_cycle&.production
      Entry.new(
        occurred_at: req.created_at,
        kind: :audition_request,
        title: "Signed up to audition",
        subtitle: production&.name,
        details: nil,
        url: production && req.audition_cycle ? Rails.application.routes.url_helpers.manage_signups_auditions_cycle_request_path(production, req.audition_cycle, req) : nil,
        answers: req.answers.to_a
      )
    end
  end

  def audition_entries(limit, before)
    scope = Audition
      .joins(:audition_session)
      .where(auditionable_type: "Person", auditionable_id: @person.id)
    scope = scope_with_cursor(scope, "audition_sessions.start_at", before, limit)
      .includes(audition_session: [ :location, { audition_cycle: :production } ])

    scope.filter_map do |audition|
      session = audition.audition_session
      next unless session

      cycle = session.audition_cycle
      production = cycle&.production
      Entry.new(
        occurred_at: session.start_at,
        kind: :audition,
        title: "Auditioned",
        subtitle: production&.name,
        details: session.location&.name,
        url: production && cycle ? Rails.application.routes.url_helpers.manage_signups_auditions_cycle_session_audition_path(production, cycle, session, audition) : nil,
        answers: []
      )
    end
  end

  def sign_up_entries(limit, before)
    scope = @person.sign_up_registrations
    scope = scope_with_cursor(scope, "sign_up_registrations.registered_at", before, limit)
      .includes(sign_up_slot: { sign_up_form_instance: [ :show, { sign_up_form: :production } ] })

    scope.map do |reg|
      slot = reg.sign_up_slot
      instance = slot&.sign_up_form_instance
      form = instance&.sign_up_form
      production = form&.production
      Entry.new(
        occurred_at: reg.registered_at,
        kind: :sign_up,
        title: "Signed up for #{form&.name.presence || 'sign-up'}",
        subtitle: production&.name,
        details: instance&.show&.respond_to?(:display_name) ? instance.show.display_name : nil,
        url: nil,
        answers: []
      )
    end
  end

  def course_entries(limit, before)
    scope = @person.course_registrations
    scope = scope_with_cursor(scope, "course_registrations.registered_at", before, limit)
      .includes(course_offering: :production)

    scope.map do |reg|
      offering = reg.course_offering
      production = offering&.production
      Entry.new(
        occurred_at: reg.registered_at,
        kind: :course,
        title: "Registered for #{offering&.title.presence || 'course'}",
        subtitle: production&.name,
        details: reg.status&.titleize,
        url: nil,
        answers: []
      )
    end
  end

  def audition_acceptance_entries(limit, before)
    scope = Audition
      .where(auditionable_type: "Person", auditionable_id: @person.id)
      .where.not(accepted_at: nil)
    scope = scope_with_cursor(scope, "auditions.accepted_at", before, limit)
      .includes(audition_session: { audition_cycle: :production })

    scope.map do |audition|
      cycle = audition.audition_session&.audition_cycle
      production = cycle&.production
      Entry.new(
        occurred_at: audition.accepted_at,
        kind: :audition_accepted,
        title: "Accepted audition invitation",
        subtitle: production&.name,
        details: audition.audition_session&.start_at&.strftime("%a %b %-d, %-l:%M %p"),
        url: nil,
        answers: []
      )
    end
  end

  def audition_session_availability_entries(limit, before)
    scope = AuditionSessionAvailability
      .where(available_entity_type: "Person", available_entity_id: @person.id)
      .where.not(status: AuditionSessionAvailability.statuses[:unset])
    scope = scope_with_cursor(scope, "audition_session_availabilities.updated_at", before, limit)
      .includes(audition_session: { audition_cycle: :production })

    scope.map do |sa|
      session = sa.audition_session
      cycle = session&.audition_cycle
      production = cycle&.production
      status_label = sa.status == "available" ? "available" : "unavailable"
      Entry.new(
        occurred_at: sa.updated_at,
        kind: :audition_session_availability,
        title: "Marked #{status_label} for audition session",
        subtitle: production&.name,
        details: session&.start_at&.strftime("%a %b %-d, %-l:%M %p"),
        url: nil,
        answers: []
      )
    end
  end

  def vacancy_created_entries(limit, before)
    # vacated_at may be nil on older records; fall back to created_at.
    sort_expr = "COALESCE(role_vacancies.vacated_at, role_vacancies.created_at)"
    scope = RoleVacancy.where(vacated_by_type: "Person", vacated_by_id: @person.id)
    scope = scope_with_cursor(scope, sort_expr, before, limit).includes(:show, :role)

    scope.map do |v|
      Entry.new(
        occurred_at: v.vacated_at || v.created_at,
        kind: :vacancy_created,
        title: "Said they can't make it",
        subtitle: v.show&.respond_to?(:display_name) ? v.show.display_name : nil,
        details: [ v.role&.name, v.show&.date_and_time&.strftime("%a %b %-d") ].compact.join(" · "),
        url: nil,
        answers: []
      )
    end
  end

  def vacancy_filled_entries(limit, before)
    scope = RoleVacancy
      .where(filled_by_id: @person.id)
      .where.not(filled_at: nil)
    scope = scope_with_cursor(scope, "role_vacancies.filled_at", before, limit).includes(:show, :role)

    scope.map do |v|
      Entry.new(
        occurred_at: v.filled_at,
        kind: :vacancy_filled,
        title: "Accepted a vacancy",
        subtitle: v.show&.respond_to?(:display_name) ? v.show.display_name : nil,
        details: [ v.role&.name, v.show&.date_and_time&.strftime("%a %b %-d") ].compact.join(" · "),
        url: nil,
        answers: []
      )
    end
  end

  def cast_assignment_entries(limit, before)
    scope = ShowPersonRoleAssignment
      .where(assignable_type: "Person", assignable_id: @person.id)
      .joins(:show)
      .where.not(shows: { casting_finalized_at: nil })
    scope = scope_with_cursor(scope, "shows.casting_finalized_at", before, limit)
      .includes(:role, show: :production)

    scope.map do |assignment|
      show = assignment.show
      Entry.new(
        occurred_at: show.casting_finalized_at,
        kind: :cast,
        title: "Cast as #{assignment.role&.name.presence || 'a role'}",
        subtitle: show.production&.name,
        details: show.respond_to?(:display_name) ? "#{show.display_name} · #{show.date_and_time&.strftime('%a %b %-d')}" : show.date_and_time&.strftime("%a %b %-d"),
        url: nil,
        answers: []
      )
    end
  end
end
