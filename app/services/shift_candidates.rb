# frozen_string_literal: true

# Who could work a shift (V1.1 plan §5): everyone qualified for its role,
# with what they said about the hours, whether they're on the shift already,
# in a show that night or on another shift that overlaps. Free for all of it
# first, then partly, then hasn't said, then can't; a clash sorts after the
# clean ones of its kind; whoever's on the shift, can't make it or was asked
# already comes last. The staff scope of the People Picker reads it, a shift
# vacancy's invite list reads it, and a claim page reads one person's row of
# it for their own warnings.
class ShiftCandidates
  FIT = { "free" => 0, "partial" => 2, "unknown" => 4, "blocked" => 6 }.freeze
  HEADSHOTS = { profile_headshots: { image_attachment: :blob } }.freeze

  Row = Struct.new(:person, :status, :verdict, :cast, :conflicts, :on_shift, :excluded, :invited, keyword_init: true) do
    def free? = status == "free"
    def clash? = cast.any? || conflicts.any?
    def pickable? = !on_shift && !excluded && !invited
  end

  attr_reader :shift

  # query: what was typed (two characters or more narrows the list);
  # fit: all | can_work | free; exclude_keys: "Person_12" (or "12") keys the
  # page keeps out, worded exclude_label; invited_ids: people asked already.
  def initialize(shift, query: "", fit: "all", exclude_keys: [], exclude_label: nil, invited_ids: [])
    @shift = shift
    @organization = shift.organization
    @query = query.to_s.strip
    @fit = fit.to_s.presence_in(%w[all can_work free]) || "all"
    @excluded_ids = Array(exclude_keys).flat_map { |k| k.to_s.split(",") }
                                       .map { |k| k.delete_prefix("Person_").to_i }.reject(&:zero?).to_set
    @exclude_label = exclude_label.presence || "Already added"
    @invited_ids = Array(invited_ids).flat_map { |k| k.to_s.split(",") }.map(&:to_i).reject(&:zero?).to_set
  end

  def rows
    @rows ||= build_rows(qualified_people)
  end

  # One person's picture, qualified or not (the claim page's warnings).
  def row_for(person)
    build_rows([ person ]).first
  end

  # Free for the whole shift (said so, or hasn't said otherwise: the picker's
  # "Available the whole shift"), no clash, and still to be asked: the "Add
  # everyone who's free" list.
  def free
    rows.select { |r| r.status.in?(%w[free unknown]) && !r.clash? && r.pickable? }
  end

  # The People Picker's locals (shared/people_picker/results).
  def picker_locals
    already = {}
    badges = Hash.new { |h, k| h[k] = [] }
    extras = {}
    rows.each do |r|
      key = "Person_#{r.person.id}"
      if r.on_shift then already[key] = "Assigned"
      elsif r.excluded then already[key] = @exclude_label
      elsif r.invited then already[key] = "Already invited"
      elsif r.cast.any? then badges[key] << "In a show"
      elsif r.status == "blocked" then badges[key] << "Unavailable"
      elsif r.status == "partial" then badges[key] << (r.verdict[:badge] || "Partly available")
      elsif r.status == "unknown" then badges[key] << "Hasn't said"
      end
      badges[key] << "On another shift" if r.conflicts.any? && !r.on_shift
      extras[key] = { pick: { staff: { verdict: r.verdict, cast: r.cast, conflicts: r.conflicts } } }
    end
    { people: rows.map(&:person), already: already, badges: badges, extras: extras,
      heading: "Qualified for #{shift.house_role.name}",
      empty: (@fit == "all" ? "No one is qualified for this role yet." : "No one who can work this shift.") }
  end

  private

  def qualified_people
    members = StaffRoleQualification.joins(organization_staff_member: :person)
                                    .where(house_role_id: shift.house_role_id,
                                           organization_staff_members: { organization_id: @organization.id, archived_at: nil })
                                    .includes(organization_staff_member: { person: HEADSHOTS })
                                    .order("people.name").map(&:organization_staff_member)
    members.select! { |m| m.person.name.to_s.downcase.include?(@query.downcase) } if @query.length >= 2
    members.map(&:person)
  end

  def build_rows(people)
    ids = people.map(&:id)
    resolver = StaffAvailabilityResolver.new(ids, from: shift.starts_at.to_date, to: shift.ends_at.to_date)
    on_shift = shift.active_assignments.map(&:person_id).to_set
    day = shift.source.is_a?(Show) ? shift.source.date_and_time.to_date : shift.starts_at.to_date
    shows = Show.joins(:production).where(productions: { organization_id: @organization.id }, date_and_time: day.all_day).includes(:production)
    cast = ShowPersonRoleAssignment.where(show_id: shows.map(&:id), assignable_type: "Person", assignable_id: ids)
                                   .group_by(&:assignable_id).transform_values { |as| as.map(&:show_id).uniq }
    show_label = shows.index_by(&:id).transform_values { |show| "#{show.production&.name} (#{show.date_and_time.strftime("%-l:%M %p")})" }
    overlapping = @organization.shifts.where("starts_at < ? AND ends_at > ?", shift.ends_at, shift.starts_at).where.not(id: shift.id)
                               .includes(:house_role, shift_assignments: []).to_a
    busy = overlapping.each_with_object(Hash.new { |h, k| h[k] = [] }) do |other, h|
      other.active_assignments.each do |a|
        h[a.person_id] << { role: other.house_role.name, day: other.starts_at.strftime("%a %b %-d"),
                            time_range: "#{other.starts_at.strftime("%-l:%M %p")}–#{other.ends_at.strftime("%-l:%M %p")}" }
      end
    end

    rows = people.map do |person|
      verdict = resolver.verdict(person.id, shift.starts_at, shift.ends_at)
      status = verdict.status.to_s
      Row.new(person: person, status: status,
              verdict: { status: status, badge: StaffAvailabilityWording.badge(verdict), detail: StaffAvailabilityWording.detail(verdict) },
              cast: (cast[person.id] || []).map { |id| show_label[id] }.compact, conflicts: busy[person.id],
              on_shift: on_shift.include?(person.id), excluded: @excluded_ids.include?(person.id), invited: @invited_ids.include?(person.id))
    end
    rows.select! { |r| r.status != "blocked" } if @fit == "can_work"
    rows.select! { |r| r.status.in?(%w[free unknown]) } if @fit == "free"
    rows.sort_by!.with_index { |r, i| [ rank(r), i ] }
    rows
  end

  def rank(row)
    return 9 if row.on_shift
    return 8 unless row.pickable?

    FIT.fetch(row.status, 4) + (row.clash? ? 1 : 0)
  end
end
