# frozen_string_literal: true

# What a registrant hears when a course they'd signed up for is cancelled.
# Sent by CourseCancellationJob to everyone refunded or removed. Channel "both":
# an in-app message if they have an account, and an email either way. All copy
# lives here — nothing is hardcoded in the job.
class CreateCourseCancelledContentTemplate < ActiveRecord::Migration[8.1]
  KEY = "course_cancelled_registrant"

  def up
    ContentTemplate.find_or_create_by!(key: KEY) do |t|
      t.name = "Course Cancelled"
      t.description = "Sent to registrants when a course they were registered for is cancelled"
      t.category = "courses"
      t.channel = "both"
      t.template_type = "structured"
      t.active = true
      t.subject = "{{course_title}} has been cancelled"
      t.body = <<~HTML
        <p>Hi {{recipient_name}},</p>
        <p>We're sorry — <strong>{{course_title}}</strong> with {{organization_name}} has been cancelled and won't be running.</p>
        {{#refund_amount}}<p>Your payment of <strong>{{refund_amount}}</strong> has been refunded to the card you paid with. Refunds usually appear within 5–10 business days, depending on your bank.</p>{{/refund_amount}}
        <p>If you have any questions, please contact {{organization_name}} directly.</p>
      HTML
      t.message_body = <<~HTML
        <div>Hi {{recipient_name}},<br><br>We're sorry — <strong>{{course_title}}</strong> with {{organization_name}} has been cancelled and won't be running.<br><br>{{#refund_amount}}Your payment of <strong>{{refund_amount}}</strong> has been refunded to the card you paid with. Refunds usually appear within 5–10 business days, depending on your bank.<br><br>{{/refund_amount}}If you have any questions, please contact {{organization_name}} directly.</div>
      HTML
      t.available_variables = [
        { "name" => "recipient_name", "description" => "Registrant's first name" },
        { "name" => "course_title", "description" => "Title of the course offering" },
        { "name" => "organization_name", "description" => "The organization running the course" },
        { "name" => "refund_amount", "description" => "Formatted amount refunded (blank when nothing was paid)" }
      ]
    end
  end

  def down
    ContentTemplate.find_by(key: KEY)&.destroy
  end
end
