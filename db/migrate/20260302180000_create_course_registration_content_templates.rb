# frozen_string_literal: true

class CreateCourseRegistrationContentTemplates < ActiveRecord::Migration[8.0]
  def up
    # 1. Confirmation email + in-app message to the registrant
    ContentTemplate.find_or_create_by!(key: "course_registration_confirmed") do |t|
      t.name = "Course Registration Confirmed"
      t.description = "Sent to the registrant after their course purchase is confirmed"
      t.category = "courses"
      t.channel = "both"
      t.template_type = "structured"
      t.active = true
      t.subject = "You're registered for {{course_title}}!"
      t.body = <<~HTML
        <p>Hi {{recipient_name}},</p>
        <p>Your registration for <strong>{{course_title}}</strong> has been confirmed.</p>
        <p><strong>Amount Paid:</strong> {{amount_paid}}</p>
        {{#instructor_name}}<p><strong>Instructor:</strong> {{instructor_name}}</p>{{/instructor_name}}
        {{#class_schedule}}<p><strong>Class Schedule:</strong><br>{{class_schedule}}</p>{{/class_schedule}}
        <p>You can view your class schedule and details on your <a href="{{dashboard_url}}">CocoScout dashboard</a>.</p>
        <p>If you have any questions, please contact the organizer directly.</p>
      HTML
      t.message_body = <<~HTML
        <div>Hi {{recipient_name}},<br><br>Your registration for <strong>{{course_title}}</strong> has been confirmed.<br><br><strong>Amount Paid:</strong> {{amount_paid}}<br>{{#instructor_name}}<strong>Instructor:</strong> {{instructor_name}}<br>{{/instructor_name}}{{#class_schedule}}<strong>Class Schedule:</strong><br>{{class_schedule}}<br><br>{{/class_schedule}}You can view your class schedule and details on your <a href="{{dashboard_url}}">CocoScout dashboard</a>.<br><br>If you have any questions, please contact the organizer directly.</div>
      HTML
      t.available_variables = [
        { "name" => "recipient_name", "description" => "Registrant's first name" },
        { "name" => "course_title", "description" => "Title of the course offering" },
        { "name" => "amount_paid", "description" => "Formatted amount paid (e.g., $150)" },
        { "name" => "instructor_name", "description" => "Name of the instructor (optional)" },
        { "name" => "class_schedule", "description" => "List of upcoming class dates" },
        { "name" => "dashboard_url", "description" => "URL to the user's dashboard" }
      ]
    end

    # 2. In-app message to the producer/team when someone registers
    ContentTemplate.find_or_create_by!(key: "course_registration_producer_notification") do |t|
      t.name = "Course Registration Producer Notification"
      t.description = "In-app notification sent to the production team when someone registers for a course"
      t.category = "courses"
      t.channel = "message"
      t.template_type = "structured"
      t.active = true
      t.subject = "New registration for {{course_title}}"
      t.body = <<~HTML
        <div><strong>{{registrant_name}}</strong> has registered for <strong>{{course_title}}</strong>.<br><br><strong>Amount:</strong> {{amount_paid}}<br><strong>Total Registrations:</strong> {{total_registrations}}<br>{{#spots_remaining}}<strong>Spots Remaining:</strong> {{spots_remaining}}<br>{{/spots_remaining}}<br><a href="{{course_offering_url}}">View all registrations</a></div>
      HTML
      t.available_variables = [
        { "name" => "registrant_name", "description" => "Name of the person who registered" },
        { "name" => "course_title", "description" => "Title of the course offering" },
        { "name" => "amount_paid", "description" => "Formatted amount paid" },
        { "name" => "total_registrations", "description" => "Total confirmed registrations" },
        { "name" => "spots_remaining", "description" => "Number of spots remaining (if capacity set)" },
        { "name" => "course_offering_url", "description" => "URL to the course offering management page" }
      ]
    end
  end

  def down
    ContentTemplate.where(key: %w[course_registration_confirmed course_registration_producer_notification]).destroy_all
  end
end
