class MigrateAgreementTemplateContentToActionText < ActiveRecord::Migration[8.1]
  def up
    # Migrate existing plain text content to ActionText rich text
    AgreementTemplate.find_each do |template|
      # Convert markdown-style content to basic HTML
      old_content = template.read_attribute(:content)
      next if old_content.blank?

      # Simple markdown to HTML conversion
      html_content = old_content
        .gsub(/^# (.+)$/, '<h1>\1</h1>')
        .gsub(/^## (.+)$/, '<h2>\1</h2>')
        .gsub(/^### (.+)$/, '<h3>\1</h3>')
        .gsub(/\*\*(.+?)\*\*/, '<strong>\1</strong>')
        .gsub(/\*(.+?)\*/, '<em>\1</em>')
        .gsub(/^- (.+)$/) { "<li>#{$1}</li>" }
        .gsub(/((?:<li>.+<\/li>\n?)+)/) { "<ul>#{$1}</ul>" }
        .gsub(/\n\n/, '</p><p>')
        .then { |s| "<p>#{s}</p>" }
        .gsub(/<p><h/, '<h')
        .gsub(/<\/h(\d)><\/p>/, '</h\1>')
        .gsub(/<p><ul>/, '<ul>')
        .gsub(/<\/ul><\/p>/, '</ul>')

      template.content = html_content
      template.save!(validate: false)
    end

    # Remove the old content column after migration
    remove_column :agreement_templates, :content
  end

  def down
    add_column :agreement_templates, :content, :text

    # Convert ActionText back to plain text (best effort)
    AgreementTemplate.find_each do |template|
      next unless template.content.present?

      plain_text = template.content.to_plain_text
      template.update_column(:content, plain_text)
    end
  end
end
