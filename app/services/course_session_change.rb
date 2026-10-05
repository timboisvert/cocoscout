# frozen_string_literal: true

# A session that moved after students registered: a new date, time or place.
# Each confirmed registration remembers what the student was told about
# every session (told_sessions, taken when they registered). The ones told
# something else are who to tell. Nothing goes out by itself: the course
# page asks, the manager reads and edits the email first (the
# course_session_changed template), and CourseSessionChangeJob sends it,
# one per moved session, each with that student's own "it was". "Mark as
# told" settles it without an email.
class CourseSessionChange
  Draft = Data.define(:registrations, :subject, :body)
  Moved = Data.define(:show, :was_at, :was_location, :was_space)

  # What every session says right now, keyed by show id.
  def self.snapshot(offering)
    offering.sessions.to_h do |show|
      [ show.id.to_s, { "at" => show.date_and_time.iso8601, "location_id" => show.location_id, "space_id" => show.location_space_id } ]
    end
  end

  # The sessions a registration was told something else about.
  def self.moved(registration, sessions = registration.course_offering.sessions.includes(:location, :location_space).to_a)
    sessions.filter_map do |show|
      told = registration.told_sessions[show.id.to_s]
      next unless told
      next if told["at"] == show.date_and_time.iso8601 && told["location_id"] == show.location_id && told["space_id"] == show.location_space_id

      Moved.new(show: show, was_at: Time.zone.parse(told["at"].to_s), was_location: Location.find_by(id: told["location_id"]),
                was_space: LocationSpace.find_by(id: told["space_id"]))
    end
  end

  def self.registrations(offering)
    sessions = offering.sessions.where(canceled: false).where("date_and_time > ?", Time.current).includes(:location, :location_space).to_a
    offering.course_registrations.confirmed.includes(:person).select { |r| moved(r, sessions).any? }
  end

  # Worth asking about: a course still running, with students to tell.
  def self.pending?(offering)
    return false if offering.cancelled? || offering.archived?

    registrations(offering).any?
  end

  def self.draft(offering)
    template = ContentTemplateService.find_template("course_session_changed")
    Draft.new(registrations: registrations(offering).sort_by { |r| r.person&.name.to_s },
              subject: template&.subject.to_s, body: TicketOrderMailer.plain_text(template&.body))
  end

  def self.start!(offering, subject:, body:)
    CourseSessionChangeJob.perform_later(offering.id, subject.to_s, body.to_s)
  end

  # These students now know what the sessions say.
  def self.mark_told!(offering, registrations = registrations(offering))
    snapshot = snapshot(offering)
    Array(registrations).each { |r| r.update_columns(told_sessions: r.told_sessions.merge(snapshot)) }
    Array(registrations).size
  end

  # The words for one student's email about one moved session.
  def self.variables(registration, moved)
    show = moved.show
    CourseRegistrationMailer.variables(registration).merge(
      what_changed: what_changed(moved),
      now: described(show.date_and_time, show.location, show.location_space),
      was: described(moved.was_at || show.date_and_time, moved.was_location, moved.was_space)
    )
  end

  def self.what_changed(moved)
    show = moved.show
    words = []
    words << "date" if moved.was_at && moved.was_at.to_date != show.date_and_time.to_date
    words << "time" if moved.was_at && moved.was_at.strftime("%H:%M") != show.date_and_time.strftime("%H:%M")
    words << "place" if moved.was_location&.id != show.location_id || moved.was_space&.id != show.location_space_id
    words.to_sentence.presence || "time"
  end

  def self.described(time, location, space)
    venue = [ location&.name, space&.name ].compact.uniq.join(", ")
    [ time.strftime("%A, %B %-d at %-l:%M %p"), (" at #{venue}" if venue.present?) ].compact.join(",")
  end

  private_class_method :what_changed, :described
end
