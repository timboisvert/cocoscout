class RenameEmailTemplatesToContentTemplates < ActiveRecord::Migration[8.1]
  def change
    # Rename the table
    rename_table :email_templates, :content_templates

    # Rename indexes if they still have the old naming convention
    # PostgreSQL may or may not auto-rename indexes when table is renamed
    reversible do |dir|
      dir.up do
        rename_index_if_exists(:content_templates, "index_email_templates_on_active", "index_content_templates_on_active")
        rename_index_if_exists(:content_templates, "index_email_templates_on_category", "index_content_templates_on_category")
        rename_index_if_exists(:content_templates, "index_email_templates_on_key", "index_content_templates_on_key")
      end
      dir.down do
        rename_index_if_exists(:email_templates, "index_content_templates_on_active", "index_email_templates_on_active")
        rename_index_if_exists(:email_templates, "index_content_templates_on_category", "index_email_templates_on_category")
        rename_index_if_exists(:email_templates, "index_content_templates_on_key", "index_email_templates_on_key")
      end
    end
  end

  private

  def rename_index_if_exists(table, old_name, new_name)
    if index_exists_by_name?(old_name)
      rename_index table, old_name, new_name
    end
  end

  def index_exists_by_name?(name)
    connection.execute("SELECT 1 FROM pg_indexes WHERE indexname = '#{name}'").any?
  end
end
