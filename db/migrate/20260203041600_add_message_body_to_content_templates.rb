class AddMessageBodyToContentTemplates < ActiveRecord::Migration[8.1]
  def change
    add_column :content_templates, :message_body, :text
  end
end
