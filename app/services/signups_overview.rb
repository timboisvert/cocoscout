# frozen_string_literal: true

# The rows on the organization's Sign-ups page (/manage/signups): one per
# sign-up form or audition, not one per production (Tim, 2026-11-20).
#
# Each row is current (open, paused, scheduled, or full) or closed. A paused
# form is current while it still has dates ahead, and it says Paused: the old
# page counted it as an "active sign-up form", while the production's own
# page said none were open.
class SignupsOverview
  Row = Data.define(:kind, :production, :title, :kind_words, :kind_detail, :status, :status_tone,
                    :status_detail, :people, :review_count, :path, :closed) do
    def form? = kind == :form
    def audition? = kind == :audition
  end

  CURRENT_FORM_STATES = %i[accepting full scheduled updating initializing].freeze

  attr_reader :rows

  # path_for: a lambda (kind, production, record) -> path, so the routes stay
  # in the controller.
  def initialize(productions:, to_review:, path_for:)
    @productions = productions
    @review_counts = to_review.to_h { |i| [ i.cycle.id, i.count ] }
    @path_for = path_for
    @rows = (form_rows + audition_rows).sort_by { |r| [ r.production.name.downcase, r.audition? ? 0 : 1, r.title.downcase ] }
  end

  def current = rows.reject(&:closed)
  def closed = rows.select(&:closed)

  private

  def form_rows
    SignUpForm.where(production: @productions).not_archived
              .includes(:production, { sign_up_form_instances: [ :show, { sign_up_slots: :sign_up_registrations } ] },
                        { sign_up_slots: :sign_up_registrations })
              .map { |form| form_row(form) }
  end

  def form_row(form)
    status = form.current_status
    state = status[:state]
    next_date = status.dig(:next_event, :show_date) || status[:event_date]
    upcoming = next_date.present? && next_date > Time.current
    current = CURRENT_FORM_STATES.include?(state) || status[:accepting_registrations] ||
              (state == :paused && (upcoming || form.shared_pool?))

    words, tone, detail =
      if !current then [ "Closed", :gray, nil ]
      elsif state == :paused then [ "Paused", :gray, "Not taking sign-ups" ]
      elsif state == :full then [ "Full", :amber, nil ]
      elsif state == :scheduled then [ status[:label], :amber, nil ]
      elsif status[:accepting_registrations] then [ "Open", :green, "Taking sign-ups" ]
      else [ status[:label], :gray, nil ]
      end

    dates = form.sign_up_form_instances.size
    kind_words, kind_detail =
      if form.shared_pool? then [ "Waitlist", "Not tied to a date" ]
      elsif form.single_event? then [ "Sign-up form", "One date" ]
      else [ "Sign-up form", "#{dates} #{'date'.pluralize(dates)}" ]
      end

    people =
      if form.repeated? && upcoming then "Next date #{next_date.strftime('%b %-d')}"
      elsif status[:total_registrations].to_i.positive? then "#{status[:total_registrations]} signed up"
      elsif form.single_event? && next_date then next_date.strftime("%b %-d")
      end

    Row.new(kind: :form, production: form.production, title: form.name, kind_words: kind_words, kind_detail: kind_detail,
            status: words, status_tone: tone, status_detail: detail, people: people, review_count: 0,
            path: @path_for.call(:form, form.production, form), closed: !current)
  end

  def audition_rows
    AuditionCycle.where(production: @productions, active: true).includes(:production, :audition_requests)
                 .map { |cycle| audition_row(cycle) }
  end

  def audition_row(cycle)
    words, tone, detail =
      case cycle.timeline_status
      when :open then [ "Open", :green, cycle.closes_at ? "Taking sign-ups until #{cycle.closes_at.strftime('%b %-d')}" : "Taking sign-ups" ]
      when :upcoming then [ "Opens #{cycle.opens_at.strftime('%b %-d')}", :amber, nil ]
      when :paused then [ "Paused", :gray, "Not taking sign-ups" ]
      else [ "Closed #{cycle.closes_at.strftime('%b %-d')}", :gray, nil ]
      end

    how =
      if cycle.video_only? then "Video"
      elsif cycle.accepts_video_submissions? && cycle.accepts_in_person_auditions? then "In person or video"
      else "In person"
      end
    how = "#{how}, open sign-up" if cycle.signup_mode_open?

    signed_up = cycle.active_audition_requests_count
    Row.new(kind: :audition, production: cycle.production, title: "Auditions", kind_words: "Audition", kind_detail: how,
            status: words, status_tone: tone, status_detail: detail,
            people: signed_up.positive? ? "#{signed_up} signed up" : "Nobody yet",
            review_count: @review_counts[cycle.id].to_i,
            path: @path_for.call(:audition, cycle.production, cycle), closed: cycle.timeline_status == :closed)
  end
end
