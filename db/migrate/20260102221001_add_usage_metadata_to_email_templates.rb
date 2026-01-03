class AddUsageMetadataToEmailTemplates < ActiveRecord::Migration[8.1]
  def change
    add_column :email_templates, :usage_locations, :jsonb
    add_column :email_templates, :template_type, :string
    add_column :email_templates, :mailer_class, :string
    add_column :email_templates, :mailer_action, :string
    add_column :email_templates, :notes, :text
  end
end
