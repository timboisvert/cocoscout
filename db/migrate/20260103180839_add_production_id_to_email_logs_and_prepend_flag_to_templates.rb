class AddProductionIdToEmailLogsAndPrependFlagToTemplates < ActiveRecord::Migration[8.1]
  def change
    # Add production_id to email_logs for tracking which production an email relates to
    add_column :email_logs, :production_id, :integer
    add_index :email_logs, :production_id

    # Add prepend_production_name flag to email_templates
    # When true, the production name in square brackets is automatically added to subject
    add_column :email_templates, :prepend_production_name, :boolean, default: false
  end
end
