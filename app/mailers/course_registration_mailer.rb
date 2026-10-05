# frozen_string_literal: true

# A student's emails about a course: the confirmation (with the when-and-
# where block, every session, the receipt), a refund, being taken off, a
# session that moved or was canceled, and the reminder before a session. The
# words come from content templates (CourseTemplates); the blocks are the
# same ones ticket emails use.
class CourseRegistrationMailer < ApplicationMailer
  helper TicketingHelper
  helper CoursesHelper

  def confirmation(registration)
    @receipt = registration.total_cents.positive?
    deliver_words(registration, "course_registration_confirmed", template_name: "confirmation")
  end

  def refunded(registration, amount_cents: registration.total_cents)
    by_card = registration.stripe_payment_intent_id.present?
    deliver_words(registration, "course_registration_refunded", template_name: "words",
                  extra: { refund_amount: ActiveSupport::NumberHelper.number_to_currency(amount_cents / 100.0),
                           refund_how: (by_card ? " is on its way back to the card you paid with, usually within five to ten days" : "") })
  end

  def removed(registration)
    deliver_words(registration, "course_registration_removed", template_name: "words")
  end

  # A session that moved: the manager's edited draft of the
  # course_session_changed template, filled in for this student and session.
  def session_changed(registration, moved, subject:, body:)
    variables = CourseSessionChange.variables(registration, moved)
    deliver_edited(registration, subject: subject, body: body, variables: variables, session: moved.show, template_name: "session")
  end

  # Canceled sessions: the manager's edited draft of course_session_canceled.
  def session_canceled(registration, shows, subject:, body:)
    variables = self.class.variables(registration).merge(sessions: CourseSessionCancellation.sessions_words(shows))
    deliver_edited(registration, subject: subject, body: body, variables: variables, session: nil, template_name: "words")
  end

  # Before a session: the time and the place again.
  def reminder(registration, show)
    deliver_words(registration, "course_session_reminder", template_name: "session", session: show,
                  extra: { when: TicketOrderMailer.when_words(show.date_and_time) })
  end

  # The words every email can use.
  def self.variables(registration)
    offering = registration.course_offering
    organization = offering.production.organization
    sessions = offering.sessions.includes(:location, :location_space).to_a
    first = sessions.find { |s| s.date_and_time >= Time.current } || sessions.first
    {
      first_name: registration.person&.first_name.presence || registration.person&.name.to_s.split.first.presence || "there",
      organization_name: organization.name,
      course_title: offering.title,
      first_session: first ? first.date_and_time.strftime("%A, %B %-d at %-l:%M %p") : "",
      session_count: ActionController::Base.helpers.pluralize(sessions.size, "session"),
      venue: [ first&.location&.name, first&.location_space&.name ].compact.uniq.join(", "),
      amount_paid: ActiveSupport::NumberHelper.number_to_currency(registration.total_cents / 100.0),
      registration_url: routes.my_course_success_url(code: offering.short_code, token: registration.token, **url_options)
    }
  end

  # Where a student's questions go: the theater's support address, else the owner.
  def self.support_email(organization)
    organization.ticketing_profile&.support_email.presence || organization.owner&.email_address
  end

  def self.routes
    Rails.application.routes.url_helpers
  end

  def self.url_options
    Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
  end

  private

  def deliver_words(registration, key, template_name:, extra: {}, session: nil)
    load(registration, session)
    variables = self.class.variables(registration).merge(extra)
    @body_html = ContentTemplateService.render_body(key, variables.transform_values { |value| ERB::Util.html_escape(value.to_s) })
    deliver_from_theater(ContentTemplateService.render_subject(key, variables), template_name)
  end

  # Plain text a manager edited on a review page, {{variables}} filled in.
  def deliver_edited(registration, subject:, body:, variables:, session:, template_name:)
    load(registration, session)
    @body_html = TicketOrderMailer.paragraphs(ContentTemplate.interpolate(body.to_s, variables))
    deliver_from_theater(ContentTemplate.interpolate(subject.to_s, variables), template_name)
  end

  # session: the one session this email is about (else the next one).
  def load(registration, session)
    @registration = registration
    @offering = registration.course_offering
    @production = @offering.production
    @organization = @production.organization
    @person = registration.person
    @sessions = @offering.sessions.includes(:location, :location_space).to_a
    about = session || @sessions.find { |s| s.date_and_time >= Time.current } || @sessions.first
    @when_where = about && Ticketing::WhenWhere.for(about, notes: @offering.instruction_text.to_s.squish.presence)
  end

  def deliver_from_theater(subject, template_name)
    to = @person&.email.presence || @registration.user&.email_address
    mail(to: to, subject: subject,
         from: email_address_with_name("info@cocoscout.com", "#{@organization.name} via CocoScout"),
         reply_to: self.class.support_email(@organization), template_name: template_name)
  end
end
