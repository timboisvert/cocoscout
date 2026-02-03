class RemovePrependProductionNameFromContentTemplates < ActiveRecord::Migration[8.1]
  def change
    remove_column :content_templates, :prepend_production_name, :boolean
  end
end
