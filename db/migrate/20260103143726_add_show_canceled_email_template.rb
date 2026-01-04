# frozen_string_literal: true

class AddShowCanceledEmailTemplate < ActiveRecord::Migration[8.1]
  def up
    return unless defined?(EmailTemplate)

    EmailTemplate.find_or_create_by!(key: "show_canceled") do |template|
      template.name = "Show Canceled Notification"
      template.category = "notification"
      template.subject = "[{{production_name}}] {{event_type}} Canceled: {{event_date}}"
      template.description = "Sent to cast members when a show or event is canceled."
      template.template_type = "structured"
      template.mailer_class = "Manage::ShowMailer"
      template.mailer_action = "canceled_notification"
      template.body = <<~HTML
        <p>Hello {{recipient_name}},</p>

        <p>We're writing to let you know that the following event has been <strong>canceled</strong>:</p>

        <p>
          <strong>{{event_type}}</strong><br>
          {{production_name}}<br>
          {{event_date}}<br>
          {{#location}}{{location}}{{/location}}
        </p>

        <p>If you have any questions, please reach out to the production team.</p>
      HTML
      template.available_variables = [
        { "name" => "recipient_name", "description" => "The recipient's name" },
        { "name" => "production_name", "description" => "The name of the production" },
        { "name" => "event_type", "description" => "Type of event (Show, Rehearsal, etc.)" },
        { "name" => "event_date", "description" => "Date and time of the event" },
        { "name" => "location", "description" => "Location of the event (if applicable)" }
      ]
      template.active = true
    end
  end

  def down
    return unless defined?(EmailTemplate)

    EmailTemplate.find_by(key: "show_canceled")&.destroy
  end
end
