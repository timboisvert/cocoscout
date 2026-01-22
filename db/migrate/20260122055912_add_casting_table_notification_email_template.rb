class AddCastingTableNotificationEmailTemplate < ActiveRecord::Migration[8.1]
  def up
    EmailTemplate.find_or_create_by!(key: "casting_table_notification") do |template|
      template.name = "Casting Table Notification"
      template.category = "notification"
      template.subject = "Cast Confirmation: {{production_names}}"
      template.description = "Notifies someone they've been cast through a casting table. Multiple productions may be listed."
      template.template_type = "hybrid"
      template.mailer_class = "CastingTableMailer"
      template.mailer_action = "casting_notification"
      template.body = <<~HTML
        <p>You have been cast for the following shows:</p>
        {{shows_by_production}}
        <p>Please let us know if you have any scheduling conflicts or questions.</p>
      HTML
      template.available_variables = [
        { "name" => "production_names", "description" => "Comma-separated list of production names (e.g., 'Show A, Show B, and Show C')" },
        { "name" => "shows_by_production", "description" => "HTML sections with show dates grouped by production" }
      ]
    end
  end

  def down
    EmailTemplate.find_by(key: "casting_table_notification")&.destroy
  end
end
