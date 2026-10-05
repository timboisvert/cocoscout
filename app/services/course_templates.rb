# frozen_string_literal: true

# The words of every email a student gets about a course, in one place (as
# TicketingTemplates is for tickets). Each is a seeded ContentTemplate a
# theater can edit; CourseRegistrationMailer puts the when-and-where block,
# the sessions, the receipt and the Questions line under the words.
class CourseTemplates
  STUDENT_VARS = [
    { "name" => "first_name", "description" => "Student's first name" },
    { "name" => "organization_name", "description" => "The theater running the course" },
    { "name" => "course_title", "description" => "The course's title" },
    { "name" => "first_session", "description" => "The first (next) session, e.g. Tuesday, November 3 at 7:00 PM" },
    { "name" => "session_count", "description" => "e.g. 5 sessions" },
    { "name" => "venue", "description" => "Venue and room" },
    { "name" => "amount_paid", "description" => "What they paid, tax included, e.g. $108.00" },
    { "name" => "registration_url", "description" => "Link to their registration page" }
  ].freeze

  def self.v(*names)
    names.map { |n| n.is_a?(Hash) ? n : { "name" => n.to_s, "description" => n.to_s.humanize } }
  end

  TEMPLATES = [
    { key: "course_registration_confirmed", name: "Course Registration Confirmed", channel: "email",
      subject: "You're registered for {{course_title}}",
      body: %(<p>Hi {{first_name}},</p><p>You're in: <strong>{{course_title}}</strong> at {{organization_name}}, {{session_count}} starting {{first_session}}. Here's everything you need, and your receipt.</p>),
      variables: STUDENT_VARS },
    { key: "course_registration_refunded", name: "Course Registration Refunded", channel: "email",
      subject: "Your refund for {{course_title}}",
      body: %(<p>Hi {{first_name}},</p><p>{{organization_name}} has refunded your registration for <strong>{{course_title}}</strong>: {{refund_amount}}{{refund_how}}. Your spot is released.</p>),
      variables: STUDENT_VARS + v({ "name" => "refund_amount", "description" => "What's going back, e.g. $108.00" }, { "name" => "refund_how", "description" => "How it comes back: to the card, within days (blank when paid another way)" }) },
    { key: "course_registration_removed", name: "Course Registration Removed", channel: "email",
      subject: "Your registration for {{course_title}}",
      body: %(<p>Hi {{first_name}},</p><p>{{organization_name}} has taken you off <strong>{{course_title}}</strong>. If that's a surprise, just reply to this email.</p>),
      variables: STUDENT_VARS },
    { key: "course_session_changed", name: "Course Session Changed", channel: "email",
      subject: "{{course_title}}: a session has a new {{what_changed}}",
      body: %(<p>Hi {{first_name}},</p><p>One of your <strong>{{course_title}}</strong> sessions has a new {{what_changed}}. It was {{was}}; it's now {{now}}. If the change doesn't work for you, just reply to this email.</p>),
      variables: STUDENT_VARS + v({ "name" => "what_changed", "description" => "date, time, place, or a combination" }, { "name" => "was", "description" => "When and where the session was" }, { "name" => "now", "description" => "When and where it is now" }) },
    { key: "course_session_canceled", name: "Course Session Canceled", channel: "email",
      subject: "{{course_title}}: {{sessions}} canceled",
      body: %(<p>Hi {{first_name}},</p><p>{{organization_name}} has canceled {{sessions}} of <strong>{{course_title}}</strong>. The rest of the course goes ahead as planned. Reply to this email with any questions.</p>),
      variables: STUDENT_VARS + v({ "name" => "sessions", "description" => "The canceled session(s), e.g. the Tuesday, November 10 session" }) },
    { key: "course_session_reminder", name: "Course Session Reminder", channel: "email",
      subject: "Reminder: {{course_title}} is {{when}}",
      body: %(<p>Hi {{first_name}},</p><p>See you {{when}}! Here's where and when for <strong>{{course_title}}</strong>.</p>),
      variables: STUDENT_VARS + v({ "name" => "when", "description" => "tomorrow, on Tuesday, or on Tuesday, November 10" }) }
  ].freeze

  def self.ensure!(keys: nil, overwrite: false)
    TEMPLATES.each do |spec|
      next if keys && !keys.include?(spec[:key])

      template = ContentTemplate.find_or_initialize_by(key: spec[:key])
      next if template.persisted? && !overwrite

      template.assign_attributes(name: spec[:name], category: "courses", channel: spec[:channel], template_type: "structured",
                                 active: true, subject: spec[:subject], body: spec[:body], available_variables: spec[:variables])
      template.save!
    end
  end
end
