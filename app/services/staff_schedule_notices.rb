# frozen_string_literal: true

# What each staff member is told when a week is published or its updates
# sent (StaffingController#finalize). Per person: the week, the first time
# it's published and on Resend; otherwise one notice per thing that happened
# to them since they were last told (a new shift, a changed one, one they're
# no longer on), or one notice with sections when several things did.
#
# "Changed" is judged against what the person was told (the told_* snapshot
# on their assignment, stamped with notified_at), never against the row's
# timestamp: a merge or a note changes nothing they can see. Someone who
# said they can't make it keeps their row but is off the shift: never an
# update, never re-sent the shift they declined.
#
# Every notice names the shift (role and time), never the day alone, and
# says what remains that day when a shift comes off (Tim, 2026-11-07: "we
# don't want to lie to them").
class StaffScheduleNotices
  Item = Struct.new(:kind, :shift, :assignment, :removal, keyword_init: true) do
    def date = (shift&.starts_at || removal.shift_starts_at).to_date
  end

  attr_reader :organization, :week_start

  def initialize(organization, week_start, shifts)
    @organization = organization
    @week_start = week_start
    @week_range = week_start.beginning_of_day..(week_start + 6.days).end_of_day
    @shifts = shifts
  end

  # Where the week stands:
  #   update:        [{ person:, reason: :new | :changed | :removed }], who needs a notice
  #   current_count: people on a shift this week with nothing new to hear
  #   total:         everyone involved (on a shift, or with a pending removal)
  #   all_people:    those people, for a Resend
  #   unreachable:   those among them with no login, who can't be told
  def plan
    @plan ||= begin
      update = []
      current = 0
      people_items.each do |person, items|
        if items.empty?
          current += 1
        else
          update << { person: person, reason: reason_for(items) }
        end
      end
      all_people = people_items.keys
      { update: update.sort_by { |u| u[:person].name.to_s.downcase }, current_count: current,
        total: all_people.size, all_people: all_people, unreachable: all_people.reject(&:user) }
    end
  end

  # Tell these people. everyone: the week to anyone on a shift (a first
  # publish or Resend); otherwise each person's own changes. subject and
  # intro are the manager's words for the week notice and the several-changes
  # notice; custom_words says they changed them (so it's also a Message from
  # them). Returns { notified:, unreachable: [Person] }.
  def send!(people:, everyone:, subject:, intro:, custom_words: false, sender: nil)
    notified = 0
    unreachable = []
    people.each do |person|
      shifts = pairs_by_person.fetch(person, []).map(&:last).sort_by(&:starts_at)
      removals = removals_by_person.fetch(person, [])
      items = people_items.fetch(person) { items_for(person) }
      next if shifts.empty? && removals.empty?

      unless person.user
        unreachable << person
        next
      end

      if everyone && shifts.any?
        deliver_week(person, shifts, removals, subject: subject, intro: intro, custom_words: custom_words, sender: sender)
      elsif everyone
        deliver_items(person, items.select { |i| i.kind == :removed }, intro: intro, custom_words: false)
      else
        next if items.empty?

        deliver_items(person, items, intro: intro, custom_words: custom_words, sender: sender)
      end
      stamp!(person, shifts, removals)
      notified += 1
    end
    { notified: notified, unreachable: unreachable }
  end

  # Has this person's shift changed from what they were told? Rows told
  # before the snapshot existed fall back to the row's timestamp.
  def self.changed?(assignment, shift = assignment.shift)
    return false if assignment.notified_at.nil?
    return shift.updated_at > assignment.notified_at if assignment.told_starts_at.nil?

    assignment.told_starts_at != shift.starts_at || assignment.told_ends_at != shift.ends_at ||
      assignment.told_role_label != shift.role_label || assignment.told_location_name.to_s != shift.location_name.to_s
  end

  # The snapshot of a shift as told, for the rows of these people on it.
  def self.told_attributes(shift, at: Time.current)
    { notified_at: at, told_starts_at: shift.starts_at, told_ends_at: shift.ends_at,
      told_role_label: shift.role_label, told_location_name: shift.location_name }
  end

  # One new shift, told the moment it's given instead of with the week's
  # next updates: a manager put this person on a shift someone couldn't make
  # (Tim, 2026-11-10: "assigning them directly should notify them directly";
  # nobody should have to remember Notify updates for it). Only where the
  # notice is true and can land: the week is published, so the shift is on
  # their My Shifts, and they have a login. The row is stamped as told first,
  # so Notify updates has nothing more to say about it and a second call
  # sends nothing. Returns whether they were told.
  def self.tell_new_shift!(assignment)
    shift = assignment.shift
    person = assignment.person
    organization = shift.organization
    return false unless person&.user && StaffingFinalization.published?(organization, shift.starts_at)
    return false if ShiftAssignment.where(id: assignment.id, notified_at: nil).update_all(told_attributes(shift)).zero?

    ContentTemplateService.deliver(
      template_key: "staff_shift_added",
      variables: ShiftWords.variables(shift, person).compact,
      sender: nil,
      recipients: [ person ],
      organization: organization,
      message_type: :system,
      visibility: :personal,
      mailer_class: StaffingNoticeMailer.with(organization_id: organization.id),
      mailer_method: :notice
    )
    true
  end

  private

  def pairs_by_person
    @pairs_by_person ||= begin
      pairs = Hash.new { |h, k| h[k] = [] }
      @shifts.each do |shift|
        shift.active_assignments.each { |a| pairs[a.person] << [ a, shift ] if a.person }
      end
      pairs.default = nil
      pairs
    end
  end

  def removals_by_person
    @removals_by_person ||= organization.staff_schedule_removals.pending.where(shift_starts_at: @week_range)
                                        .includes(:person).to_a.group_by(&:person).tap { |h| h.delete(nil) }
  end

  def people_items
    @people_items ||= (pairs_by_person.keys + removals_by_person.keys).uniq.index_with { |person| items_for(person) }
  end

  def items_for(person)
    items = pairs_by_person.fetch(person, []).filter_map do |assignment, shift|
      if assignment.notified_at.nil? then Item.new(kind: :new, shift: shift, assignment: assignment)
      elsif self.class.changed?(assignment, shift) then Item.new(kind: :changed, shift: shift, assignment: assignment)
      end
    end
    items += removals_by_person.fetch(person, []).map { |r| Item.new(kind: :removed, removal: r) }
    pair_swaps(items)
  end

  # Off one shift and onto another the same day reads as one change
  # ("Instead of Bartender, you're on Door"), not as two events.
  def pair_swaps(items)
    removed = items.select { |i| i.kind == :removed }
    items.map do |item|
      next item unless item.kind == :new

      partner = removed.find { |r| r.date == item.date }
      next item unless partner

      removed.delete(partner)
      Item.new(kind: :swapped, shift: item.shift, assignment: item.assignment, removal: partner.removal)
    end - (items.select { |i| i.kind == :removed } - removed)
  end

  def reason_for(items)
    kinds = items.map(&:kind)
    if kinds.include?(:new) then :new
    elsif kinds.include?(:changed) || kinds.include?(:swapped) then :changed
    else :removed
    end
  end

  # -- the notices -----------------------------------------------------------

  def deliver_week(person, shifts, removals, subject:, intro:, custom_words:, sender:)
    deliver("staff_schedule_notification", person,
            variables: {
              recipient_name: ShiftWords.first_name(person),
              organization_name: organization.name,
              week_label: week_label,
              shift_count_words: "#{shifts.size} #{'shift'.pluralize(shifts.size)}",
              intro: ERB::Util.html_escape(intro),
              shifts_list: shifts.map { |s| ShiftWords.list_item(s) }.join,
              removals_list: removals.map(&:list_item).join,
              my_shifts_link: ShiftWords.my_shifts_url
            },
            subject_override: subject, custom_words: custom_words, sender: sender)
  end

  def deliver_items(person, items, intro:, custom_words:, sender: nil)
    return if items.empty?

    if items.one?
      item = items.first
      case item.kind
      when :new then deliver("staff_shift_added", person, variables: ShiftWords.variables(item.shift, person))
      when :changed, :swapped then deliver("staff_shift_changed", person, variables: change_variables(item, person))
      when :removed then deliver("staff_shift_removed", person, variables: removal_variables(item.removal, person))
      end
    else
      deliver("staff_schedule_changes", person, variables: changes_variables(items, person, intro), custom_words: custom_words, sender: sender)
    end
  end

  def deliver(template_key, person, variables:, subject_override: nil, custom_words: false, sender: nil)
    ContentTemplateService.deliver(
      template_key: template_key,
      variables: variables.compact,
      subject_override: subject_override,
      sender: (sender if custom_words),
      recipients: [ person ],
      organization: organization,
      message_type: :system,
      visibility: :personal,
      custom_words: custom_words,
      mailer_class: StaffingNoticeMailer.with(organization_id: organization.id),
      mailer_method: :notice
    )
  end

  # -- the words -------------------------------------------------------------

  def week_label = week_start.strftime("%B %-d")

  # What differs from what they were told, as a title and a list.
  def change_variables(item, person)
    shift = item.shift
    vars = ShiftWords.variables(shift, person)
    lines = change_lines(item)
    vars.merge(change_title: change_title(item, lines), changes_list: "<ul style=\"padding-left:18px;margin:8px 0;\">#{lines.map { |l| "<li>#{l}</li>" }.join}</ul>")
  end

  # [[what, was, now], ...] in words, escaped.
  def change_lines(item)
    e = ->(s) { ERB::Util.html_escape(s) }
    shift = item.shift
    if item.kind == :swapped
      r = item.removal
      return [ "Instead of <s>#{e.call(r.shift_label)}, #{e.call(r.hours)}</s> → <strong>#{e.call(shift.role_label)}, #{e.call(ShiftWords.shift_hours(shift))}</strong>" ]
    end

    a = item.assignment
    lines = []
    if a.told_starts_at.nil?
      lines << "<strong>#{e.call(ShiftWords.day(shift.starts_at))}, #{e.call(ShiftWords.shift_hours(shift))}</strong>"
      return lines
    end
    if a.told_starts_at.to_date != shift.starts_at.to_date
      lines << "Day: <s>#{e.call(ShiftWords.day(a.told_starts_at))}</s> → <strong>#{e.call(ShiftWords.day(shift.starts_at))}</strong>"
    end
    was_hours = ShiftWords.hours(a.told_starts_at, a.told_ends_at || a.told_starts_at)
    now_hours = ShiftWords.shift_hours(shift)
    lines << "Time: <s>#{e.call(was_hours)}</s> → <strong>#{e.call(now_hours)}</strong>" if was_hours != now_hours
    if a.told_role_label.present? && a.told_role_label != shift.role_label
      lines << "Role: <s>#{e.call(a.told_role_label)}</s> → <strong>#{e.call(shift.role_label)}</strong>"
    end
    if a.told_location_name.to_s != shift.location_name.to_s
      lines << "Where: <s>#{e.call(a.told_location_name.presence || 'no place set')}</s> → <strong>#{e.call(shift.location_name.presence || 'no place set')}</strong>"
    end
    lines.presence || [ "<strong>#{e.call(ShiftWords.day(shift.starts_at))}, #{e.call(now_hours)}</strong>" ]
  end

  # The push line and subject: the one thing that changed, or "Changes to".
  def change_title(item, lines)
    shift = item.shift
    short = ShiftWords.date_short(shift.starts_at)
    return "Instead of #{item.removal.shift_label}, you're on #{shift.role_label}, #{short}, #{ShiftWords.shift_hours(shift)}" if item.kind == :swapped

    a = item.assignment
    kinds = lines.map { |l| l[/\A(\w+):/, 1] }.compact
    case kinds
    when [ "Time" ] then "New time for your #{shift.role_label} shift, #{short}: #{ShiftWords.shift_hours(shift)}"
    when [ "Role" ] then "Your #{short} shift is now #{shift.role_label}"
    when [ "Where" ] then "Your #{shift.role_label} shift, #{short}, is now at #{shift.location_name.presence || 'no set place'}"
    else
      if a.told_starts_at && a.told_starts_at.to_date != shift.starts_at.to_date
        "Your #{a.told_role_label.presence || shift.role_label} shift moved: now #{short}, #{ShiftWords.start_time(shift.starts_at)}"
      else
        "Changes to your #{shift.role_label} shift, #{short}"
      end
    end
  end

  # A shift that came off: what remains that day, or the day part they have
  # back; then the rest of their week.
  def removal_variables(removal, person)
    day = removal.shift_starts_at.to_date
    mine = pairs_by_person.fetch(person, []).map(&:last).sort_by(&:starts_at)
    same_day, rest = mine.partition { |s| s.starts_at.to_date == day }
    {
      recipient_name: ShiftWords.first_name(person),
      organization_name: organization.name,
      role_label: removal.shift_label.to_s,
      shift_day: ShiftWords.day(removal.shift_starts_at),
      shift_date_short: ShiftWords.date_short(removal.shift_starts_at),
      shift_hours: removal.hours,
      start_time: ShiftWords.start_time(removal.shift_starts_at),
      location_name: removal.location_name.presence,
      remaining_line: remaining_line(same_day),
      remaining_list: same_day.map { |s| ShiftWords.list_item(s) }.join.presence,
      day_back: (ShiftWords.day_part(removal.shift_starts_at) if same_day.empty?),
      rest_list: rest.map { |s| ShiftWords.list_item(s) }.join.presence,
      my_shifts_link: ShiftWords.my_shifts_url
    }
  end

  # "You're still on Door that night, 8:00–11:00 PM." for the push line.
  def remaining_line(same_day)
    return nil if same_day.empty?

    words = same_day.map { |s| "#{s.role_label} #{ShiftWords.that_day(s.starts_at)}, #{ShiftWords.shift_hours(s)}" }
    "You're still on #{words.to_sentence}."
  end

  def changes_variables(items, person, intro)
    groups = { "New" => [], "Changed" => [], "No longer scheduled" => [] }
    items.each do |item|
      case item.kind
      when :new then groups["New"] << ShiftWords.list_item(item.shift)
      when :changed, :swapped
        groups["Changed"] << "<li style=\"margin-bottom:6px;\"><a href=\"#{ShiftWords.shift_url(item.shift)}\"><strong>#{ERB::Util.html_escape(ShiftWords.day(item.shift.starts_at))}</strong></a> · #{ERB::Util.html_escape(item.shift.role_label)}: #{change_lines(item).join('; ')}</li>"
      when :removed
        same_day = pairs_by_person.fetch(person, []).map(&:last).select { |s| s.starts_at.to_date == item.removal.shift_starts_at.to_date }
        note = remaining_line(same_day)
        groups["No longer scheduled"] << item.removal.list_item.sub("</li>", "#{note ? " (#{ERB::Util.html_escape(note.sub(/\.\z/, '').sub(/\AYou're/, "you're"))})" : ''}</li>")
      end
    end
    counts = { "New" => "new", "Changed" => "changed", "No longer scheduled" => "no longer scheduled" }
    summary = groups.filter_map { |name, list| "#{list.size} #{counts[name]}" if list.any? }.join(", ")
    sections = groups.filter_map do |name, list|
      next if list.empty?

      "<p style=\"margin:10px 0 4px;\"><strong>#{name}</strong></p><ul style=\"padding-left:18px;margin:0 0 8px;\">#{list.join}</ul>"
    end.join
    {
      recipient_name: ShiftWords.first_name(person),
      organization_name: organization.name,
      week_label: week_label,
      count_words: "#{items.size} #{'change'.pluralize(items.size)}",
      summary: summary,
      intro: ERB::Util.html_escape(intro),
      sections: sections,
      my_shifts_link: ShiftWords.my_shifts_url
    }
  end

  # -- after sending -----------------------------------------------------------

  def stamp!(person, shifts, removals)
    now = Time.current
    shifts.each do |shift|
      shift.shift_assignments.where(person_id: person.id).update_all(self.class.told_attributes(shift, at: now))
    end
    StaffScheduleRemoval.where(id: removals.map(&:id)).update_all(notified_at: now, updated_at: now)
  end
end
