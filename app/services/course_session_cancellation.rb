# frozen_string_literal: true

# Class sessions canceled in Shows & Events: the students registered for
# them, and the email they get (the course_session_canceled template, read
# and edited by the manager on the cancel screen). Canceling the whole course
# is CourseCancellationJob, which has its own email.
class CourseSessionCancellation
  Summary = Data.define(:registrations) do
    def any?
      registrations.any?
    end
  end

  def self.default_email
    template = ContentTemplateService.find_template("course_session_canceled")
    [ template&.subject.to_s, TicketOrderMailer.plain_text(template&.body) ]
  end

  # Who'd be told if these shows were canceled: confirmed registrations on
  # the course sessions among them, each once.
  def self.summary(shows)
    offering_ids = shows.filter_map(&:course_offering_id).uniq
    Summary.new(registrations: CourseRegistration.confirmed.where(course_offering_id: offering_ids).includes(:person).order(:id).to_a)
  end

  def self.start!(shows, subject:, body:)
    ids = shows.select(&:course_offering_id).map(&:id)
    CourseSessionCancellationJob.perform_later(ids, subject.to_s, body.to_s) if ids.any?
    summary(shows).registrations.size
  end

  # "the Tuesday, November 10 session" / "the sessions on Nov 10 and Nov 17".
  def self.sessions_words(shows)
    return "the #{shows.first.date_and_time.strftime('%A, %B %-d')} session" if shows.one?

    "the sessions on #{shows.map { |s| s.date_and_time.strftime('%b %-d') }.to_sentence}"
  end
end
