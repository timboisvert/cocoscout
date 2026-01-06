class ConsolidateProductionEmailTemplates < ActiveRecord::Migration[8.1]
  def up
    # Find the two templates we're consolidating
    cast_email = EmailTemplate.find_by(key: "cast_email")
    contact_message = EmailTemplate.find_by(key: "contact_message")

    # Create the new consolidated template
    EmailTemplate.create!(
      key: "production_message",
      name: "Production Message",
      category: "notification",
      subject: "{{subject}}",
      description: "General-purpose email from production team to talent. Can be used for casting announcements, directory messages, or any production-related communication. Subject and body are fully customizable.",
      template_type: "passthrough",
      mailer_class: "Manage::ProductionMailer",
      mailer_action: "send_message",
      body: "{{body_content}}",
      available_variables: [
        { name: "subject", description: "Custom email subject" },
        { name: "body_content", description: "Custom HTML body content" }
      ],
      active: true
    )

    # Delete the old templates
    cast_email&.destroy
    contact_message&.destroy
  end

  def down
    # Recreate the original templates
    EmailTemplate.create!(
      key: "cast_email",
      name: "Cast Email (Free-form)",
      category: "notification",
      subject: "{{subject}}",
      description: "Generic casting-related email with fully customizable content.",
      template_type: "passthrough",
      mailer_class: "Manage::CastingMailer",
      mailer_action: "cast_email",
      body: "{{body_content}}",
      available_variables: [
        { name: "subject", description: "Custom email subject" },
        { name: "body_content", description: "Custom HTML body content" }
      ]
    )

    EmailTemplate.create!(
      key: "contact_message",
      name: "Contact Message",
      category: "marketing",
      subject: "{{subject}}",
      description: "General-purpose contact email from producers to talent. The subject and body are fully customizable.",
      template_type: "passthrough",
      mailer_class: "Manage::ContactMailer",
      mailer_action: "send_message",
      body: "{{body_content}}",
      available_variables: [
        { name: "subject", description: "Custom email subject" },
        { name: "body_content", description: "Custom HTML body content" }
      ]
    )

    # Delete the consolidated template
    EmailTemplate.find_by(key: "production_message")&.destroy
  end
end
