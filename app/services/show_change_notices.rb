# frozen_string_literal: true

# Telling people about a batch of ShowChanges (docs/show_change_notices_plan.md).
# Up to four sends, each its own draft and list: the cast of dates that are off
# (show_canceled), the cast of dates that moved (show_moved), and the staff of
# each (shift_canceled, shift_moved). One message per person per send, listing
# their own dates and shifts. Only people not told yet are listed; each one
# sent is recorded against every change of theirs (ShowChangeNotice).
#
# The shift actions run before the staff are told: shifts of dates that are
# off lose their people and read Not needed; shifts of dates that moved move by
# the same amount. Nothing is done to a shift until the manager sends.
class ShowChangeNotices
  Section = Data.define(:key, :audience, :template, :title, :recipients, :changes) do
    def off? = key.end_with?("_off")
    def reachable = recipients.select(&:reachable?)
    def unreachable = recipients.reject(&:reachable?)
  end

  Recipient = Data.define(:person, :changes) do
    # A login gets the message and Notification (and the email); without one,
    # the email alone.
    def reachable? = person.user.present? || person.email.present?
    def email = person.user&.email_address.presence || person.email
    def first_name = person.name.to_s.split(/\s+/).first.presence || person.name.to_s
  end

  TEMPLATES = {
    "cast_off" => "show_canceled", "cast_moved" => "show_moved",
    "staff_off" => "shift_canceled", "staff_moved" => "shift_moved"
  }.freeze

  # The placeholders that can differ per person, by send, and the one whose
  # per-person version is listed under the draft.
  PER_PERSON = {
    "cast_off" => %w[event_date], "cast_moved" => %w[dates changes],
    "staff_off" => %w[dates what shifts], "staff_moved" => %w[dates what shifts]
  }.freeze
  MAIN_KEY = { "cast_off" => "event_date", "cast_moved" => "changes", "staff_off" => "shifts", "staff_moved" => "shifts" }.freeze

  TITLES = {
    "cast_off" => "Cast", "cast_moved" => "Cast",
    "staff_off" => "Staff", "staff_moved" => "Staff"
  }.freeze

  attr_reader :organization, :changes

  def initialize(organization, changes)
    @organization = organization
    @changes = changes.to_a
    @people = Person.where(id: @changes.flat_map { |c| c.cast_person_ids + c.staff_person_ids }.uniq)
                    .includes(:user).index_by(&:id)
  end

  def self.for_batch(organization, batch)
    new(organization, organization.show_changes.where(batch: batch).includes(:notices, show: [ :production, :location ]).order(:was_starts_at))
  end

  def sections
    @sections ||= TEMPLATES.keys.filter_map do |key|
      audience = key.start_with?("cast") ? "cast" : "staff"
      mine = changes.select { |c| key.end_with?("_off") ? c.off? : c.moved? }
      untold = Hash.new { |h, k| h[k] = [] }
      mine.each do |change|
        ids = audience == "cast" ? change.untold_cast_ids : change.untold_staff_ids
        ids.each { |id| untold[id] << change }
      end
      recipients = untold.filter_map { |id, list| @people[id] && Recipient.new(person: @people[id], changes: list) }
                         .sort_by { |r| r.person.name.to_s.downcase }
      next if recipients.empty?

      Section.new(key: key, audience: audience, template: TEMPLATES[key], title: TITLES[key], recipients: recipients, changes: mine)
    end
  end

  def section(key) = sections.find { |s| s.key == key }

  # The words to start from: the template with what's the same for everyone
  # filled in, and each person's own dates and shifts left as placeholders.
  # The words to start from, formatted the way every send formats a
  # template (line breaks become paragraphs). What's the same for everyone on
  # the list is filled in (a single canceled date); only what differs per
  # person stays a placeholder, with each person's version shown under it.
  def draft(section)
    template = ContentTemplateService.find_template(section.template)
    subject_vars, body_vars = common_variables(section)
    { subject: ContentTemplate.interpolate(template.subject, subject_vars),
      body: template.render_body(body_vars) }
  end

  # The placeholders left in the draft besides the first name: those whose
  # words differ from person to person.
  def per_person_keys(section)
    _subject_vars, body_vars = common_variables(section)
    PER_PERSON[section.key].reject { |key| body_vars.key?(key) }
  end

  def per_person?(section) = per_person_keys(section).include?(MAIN_KEY[section.key])

  def hint(section)
    words = { "event_date" => "their dates", "dates" => "their dates", "changes" => "each of their dates, was and now",
              "what" => "what happened", "shifts" => "their own shifts" }
    rest = per_person_keys(section).map { |key| "{{#{key}}} #{words[key]}" }
    "{{recipient_name}} becomes each person's first name#{rest.any? ? ", #{rest.to_sentence}" : ''}."
  end

  # What each person's own placeholder becomes, line by line, shown under
  # the draft so the whole message is seen before it goes.
  def filled_in(section, recipient)
    _subject_vars, body_vars = person_variables(section, recipient, projected: true)
    value = case section.key
    when "cast_off" then body_vars["event_date"]
    when "cast_moved" then body_vars["changes"]
    else body_vars["shifts"]
    end
    value.to_s.split("<br>")
  end

  def filled_in_label(section)
    case section.key
    when "cast_off" then "{{event_date}} for each person:"
    when "cast_moved" then "{{changes}} for each person:"
    else "{{shifts}} for each person:"
    end
  end

  # Sends the edited copy to the ticked people of one section. Returns how
  # many were told.
  def send!(key, person_ids:, subject:, body:, sender:, shift_action: false)
    section = section(key)
    return 0 unless section

    if section.audience == "staff" && shift_action
      section.off? ? take_shifts_off!(section) : move_shifts!(section)
    end

    default = draft(section)
    custom = ManagerWords.changed?([ subject, default[:subject] ], [ body, default[:body] ])
    ids = person_ids.map(&:to_i).to_set
    told = section.reachable.select { |r| ids.include?(r.person.id) }
    told.each do |recipient|
      subject_vars, body_vars = person_variables(section, recipient)
      shows = recipient.changes.filter_map(&:show)
      ContentTemplateService.deliver(
        template_key: section.template, variables: body_vars, sender: (sender if custom), recipients: [ recipient.person ],
        organization: organization, production: (shows.first.production if shows.map(&:production_id).uniq.one?),
        show: (shows.first if shows.one?), message_type: :system, visibility: :personal, custom_words: custom,
        mailer_class: ShowChangeMailer.with(organization_id: organization.id), mailer_method: :notice,
        subject_override: ContentTemplate.interpolate(subject, subject_vars).squish,
        body_override: ContentTemplate.interpolate(body, body_vars)
      )
      recipient.changes.each do |change|
        ShowChangeNotice.find_or_create_by!(show_change: change, person: recipient.person, audience: section.audience) do |notice|
          notice.sent_by_user = sender
        end
      end
    end
    told.size
  end

  # "Nobody needs telling": the batch is done.
  def close!
    ShowChange.where(id: changes.map(&:id)).update_all(closed_at: Time.current)
  end

  # Dates that are off: their shifts lose the people on them (anyone who
  # already logged hours stays) and read Not needed.
  def take_shifts_off!(section)
    shifts_for(section).each do |shift|
      shift.shift_assignments.includes(:staff_time_entry).each do |assignment|
        assignment.destroy! unless assignment.staff_time_entry
      end
      shift.update!(coverage_mode: :not_needed)
    end
  end

  # Dates that moved: each shift moves by as much as its date did, once (a
  # shift no longer where it was has been moved already).
  def move_shifts!(section)
    section.changes.each do |change|
      next unless change.was_starts_at && change.now_starts_at

      offset = change.now_starts_at - change.was_starts_at
      next if offset.zero?

      change.staff.uniq { |s| s["shift_id"] }.each do |entry|
        shift = organization.shifts.find_by(id: entry["shift_id"])
        next unless shift && shift.starts_at.to_i == Time.zone.parse(entry["starts_at"]).to_i

        shift.update!(starts_at: shift.starts_at + offset, ends_at: shift.ends_at + offset)
      end
    end
  end

  def shifts_for(section)
    organization.shifts.where(id: section.changes.flat_map(&:shift_ids).uniq).to_a
  end

  private

  # [subject variables, body variables] for the draft: the shared ones, plus
  # each per-person one whose words are the same for everyone on the list.
  def common_variables(section)
    @common_variables ||= {}
    @common_variables[section.key] ||= begin
      shared = shared_variables(section)
      per = section.recipients.map { |r| person_variables(section, r, projected: true) }
      subject_vars = shared.dup
      body_vars = shared.dup
      PER_PERSON[section.key].each do |key|
        bodies = per.map { |_s, b| b[key] }.uniq
        next unless bodies.one?

        body_vars[key] = bodies.first
        subject_vars[key] = per.first.first[key]
      end
      [ subject_vars, body_vars ]
    end
  end

  def shared_variables(section)
    shows = section.changes.filter_map(&:show)
    productions = section.changes.map(&:production).compact.uniq
    {
      "organization_name" => organization.name,
      "production_name" => productions.one? ? productions.first.name : organization.name,
      "event_type" => shows.first&.event_type&.titleize.presence || "Show",
      "location" => shows.first&.location&.name.to_s
    }
  end

  # [subject variables, body variables]: the same names, short in the
  # subject, a line each in the body.
  # projected: a moved shift not moved yet reads as if it were (the preview,
  # with Move these shifts ticked).
  def person_variables(section, recipient, projected: false)
    shared = shared_variables(section).merge("recipient_name" => recipient.first_name)
    changes = recipient.changes
    dates = changes.map { |c| short_date(c.moved? ? c.now_starts_at : c.was_starts_at) }.uniq.to_sentence

    vars = case section.key
    when "cast_off"
      { "event_date" => [ dates, changes.map { |c| long_time(c.was_starts_at) }.join("<br>") ] }
    when "cast_moved"
      { "dates" => dates, "changes" => [ dates, changes.map { |c| "#{long_time(c.was_starts_at)} → #{long_time(c.now_starts_at)}" }.join("<br>") ] }
    else
      { "dates" => dates, "what" => what(section, changes), "shifts" => [ dates, shift_lines(section, recipient, projected: projected).join("<br>") ] }
    end

    subject_vars = shared.merge(vars.transform_values { |v| v.is_a?(Array) ? v.first : v })
    body_vars = shared.merge(vars.transform_values { |v| v.is_a?(Array) ? v.last : v })
    [ subject_vars, body_vars ]
  end

  def what(section, changes)
    changes.map do |change|
      name = change.production&.name || change.show_label.split(" · ").first
      if section.off?
        "#{name} on #{short_date(change.was_starts_at)} #{change.kind == 'canceled' ? 'was canceled' : 'is off'}"
      elsif change.booking_only?
        "The booking for #{name} on #{short_date(change.was_starts_at)} moved to #{short_time(change.now_starts_at)}"
      else
        "#{name} moved from #{long_time(change.was_starts_at)} to #{long_time(change.now_starts_at)}"
      end
    end.to_sentence
  end

  # This person's shifts in the change: was and now when it moved.
  def shift_lines(section, recipient, projected: false)
    shifts = organization.shifts.where(id: recipient.changes.flat_map(&:shift_ids)).index_by(&:id)
    recipient.changes.flat_map do |change|
      change.staff.select { |s| s["person_id"] == recipient.person.id }.map do |entry|
        was_from = Time.zone.parse(entry["starts_at"])
        was_to = Time.zone.parse(entry["ends_at"])
        line = "#{entry['role']}, #{short_date(was_from)}, #{hours(was_from, was_to)}"
        shift = shifts[entry["shift_id"]]
        now_from, now_to = shift && [ shift.starts_at, shift.ends_at ]
        if projected && !section.off? && change.was_starts_at && change.now_starts_at && (shift.nil? || now_from.to_i == was_from.to_i)
          offset = change.now_starts_at - change.was_starts_at
          now_from, now_to = was_from + offset, was_to + offset
        end
        if !section.off? && now_from && now_from.to_i != was_from.to_i
          line += " → #{"#{short_date(now_from)}, " unless now_from.to_date == was_from.to_date}#{hours(now_from, now_to)}"
        end
        line
      end
    end.uniq
  end

  def short_date(time) = time&.strftime("%a, %b %-d")
  def short_time(time) = time&.strftime("%-l:%M %p")
  def long_time(time) = time&.strftime("%a, %b %-d, %-l:%M %p")
  def hours(from, to) = "#{from.strftime('%-l:%M')}–#{to.strftime('%-l:%M %p')}"
end
