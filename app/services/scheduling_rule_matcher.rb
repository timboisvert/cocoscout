# frozen_string_literal: true

# Matches an org's active scheduling rules ("regulars") against one week of
# events and answers: which shifts would these rules produce, and can each
# person actually take theirs? The Scheduling page renders the result as a
# review checklist; SchedulingRuleApplier turns the approved rows into real
# shifts. Read-only — this class never writes.
#
# One Match per rule-occurrence:
#   production_anchored + per-show role  → one per show of that production
#   production_anchored + house role     → one per day the production plays,
#                                          spanning the whole evening (same
#                                          window the Add-shift defaults use)
#   weekday                              → the week's one matching date, at the
#                                          rule's own times — but only when
#                                          that day has at least one event
class SchedulingRuleMatcher
  Match = Struct.new(
    :key, :rule, :person, :house_role, :date, :starts_at, :ends_at, :show,
    :existing_shift, :already_assigned, :qualified, :unavailable,
    keyword_init: true
  ) do
    # A row the modal should render pre-checked: nothing stands in its way.
    def selectable? = qualified && !already_assigned
    def prechecked? = selectable? && !unavailable
  end

  def initialize(organization:, week_start:, shows_by_day: nil, shifts: nil)
    @organization = organization
    @week_start = week_start.to_date.beginning_of_week
    @week_end = @week_start + 6.days
    @shows_by_day = shows_by_day
    @shifts = shifts
  end

  def matches
    @matches ||= build_matches
  end

  # The subset of matches whose key is in `keys` — the applier's entry point.
  # Keys that no longer match anything (rule deleted, show canceled since the
  # modal rendered) simply drop out.
  def find(keys)
    wanted = Array(keys).map(&:to_s).to_set
    matches.select { |m| wanted.include?(m.key) }
  end

  private

  def build_matches
    return [] if rules.empty?

    rules.flat_map { |rule| matches_for(rule) }
         .sort_by { |m| [ m.date, m.starts_at, m.person.name.to_s ] }
  end

  def matches_for(rule)
    member = staff_members[rule.person_id]
    return [] unless member # off staff since the rule was made — nothing to offer

    targets_for(rule).map do |date, starts_at, ends_at, show|
      existing = existing_shift_for(rule, date, starts_at, ends_at, show)
      Match.new(
        key: "#{rule.id}:#{date.iso8601}:#{show&.id || 0}",
        rule: rule,
        person: rule.person,
        house_role: rule.house_role,
        date: date,
        starts_at: starts_at,
        ends_at: ends_at,
        show: show,
        existing_shift: existing,
        already_assigned: already_assigned?(rule, date, starts_at, ends_at, existing),
        qualified: member_role_ids(member).include?(rule.house_role_id),
        unavailable: StaffUnavailability.unavailable_for?(
          mode: availability_modes[rule.person_id] || "unavailable",
          entries: unavailability_entries[rule.person_id] || [],
          time: starts_at
        )
      )
    end
  end

  # => [[date, starts_at, ends_at, show_or_nil], ...]
  def targets_for(rule)
    if rule.production_anchored?
      rule.house_role.show_specific? ? per_show_targets(rule) : per_day_targets(rule)
    else
      weekday_targets(rule)
    end
  end

  def per_show_targets(rule)
    shows_by_day.values.flatten.select { |s| s.production_id == rule.production_id }.map do |show|
      [ show.date_and_time.to_date, show.date_and_time, show.ends_at, show ]
    end
  end

  # House roles span the evening across ALL the day's events (not just this
  # production's) — the same window the scheduling page's Add-shift defaults
  # use, so a rule-made shift and a hand-made one land identically.
  def per_day_targets(rule)
    shows_by_day.select { |_, day_shows| day_shows.any? { |s| s.production_id == rule.production_id } }
                .map do |date, day_shows|
      [ date, day_shows.first.date_and_time, day_shows.last.ends_at, nil ]
    end
  end

  def weekday_targets(rule)
    date = @week_start + ((rule.day_of_week - @week_start.wday) % 7)
    return [] if shows_by_day[date].blank? # quiet day — the rule sits this week out

    starts_at = local_time_on(date, rule.starts_local_time)
    ends_at = local_time_on(date, rule.ends_local_time)
    ends_at += 1.day if ends_at <= starts_at # overnight window (e.g. 9pm–1am)
    [ [ date, starts_at, ends_at, nil ] ]
  end

  def local_time_on(date, local_time)
    date.in_time_zone.change(hour: local_time.hour, min: local_time.min)
  end

  # A shift that already fills this slot: same role covering the same show, or
  # (for free-standing windows) same role overlapping the window that day —
  # preferring an exact time match when there are several.
  def existing_shift_for(rule, date, starts_at, ends_at, show)
    candidates = shifts.select { |s| s.house_role_id == rule.house_role_id }
    candidates =
      if show
        candidates.select { |s| covers_show?(s, show) }
      else
        candidates.select { |s| s.starts_at.to_date == date && s.starts_at < ends_at && s.ends_at > starts_at }
      end
    candidates.find { |s| s.starts_at == starts_at && s.ends_at == ends_at } || candidates.first
  end

  def covers_show?(shift, show)
    (shift.source_type == "Show" && shift.source_id == show.id) ||
      shift.shows.any? { |s| s.id == show.id }
  end

  # Already on the slot's shift — or on any same-role shift overlapping the
  # window that day (a merged or hand-tweaked shift still counts as theirs).
  def already_assigned?(rule, date, starts_at, ends_at, existing)
    return true if existing&.shift_assignments&.any? { |a| a.person_id == rule.person_id }

    shifts.any? do |s|
      s.house_role_id == rule.house_role_id &&
        s.starts_at < ends_at && s.ends_at > starts_at &&
        s.shift_assignments.any? { |a| a.person_id == rule.person_id }
    end
  end

  # --- preloads (each hit once per run) ---

  def rules
    @rules ||= @organization.scheduling_rules.active
                            .includes(:person, :house_role, :production)
                            .to_a
  end

  def rule_person_ids
    @rule_person_ids ||= rules.map(&:person_id).uniq
  end

  def staff_members
    @staff_members ||= OrganizationStaffMember.active
                                              .where(organization: @organization, person_id: rule_person_ids)
                                              .includes(:staff_role_qualifications)
                                              .index_by(&:person_id)
  end

  def member_role_ids(member)
    member.staff_role_qualifications.map(&:house_role_id)
  end

  def availability_modes
    @availability_modes ||= Person.where(id: rule_person_ids).pluck(:id, :availability_mode).to_h
  end

  def unavailability_entries
    @unavailability_entries ||= StaffUnavailability
                                .where(person_id: rule_person_ids, date: @week_start..@week_end)
                                .group_by(&:person_id)
  end

  def shows_by_day
    @shows_by_day ||= ::Show.joins(:production)
                            .where(productions: { organization_id: @organization.id })
                            .where(date_and_time: @week_start.beginning_of_day..@week_end.end_of_day)
                            .where(canceled: [ false, nil ])
                            .includes(:production)
                            .order(:date_and_time)
                            .group_by { |s| s.date_and_time.to_date }
  end

  def shifts
    @shifts ||= @organization.shifts.for_week(@week_start)
                             .includes(:shift_assignments, shows: [])
                             .to_a
  end
end
