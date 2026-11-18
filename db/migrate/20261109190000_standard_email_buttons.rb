# frozen_string_literal: true

# One email button (EmailButton; Tim, 2026-11-09). The stored templates had
# five hand-drawn ones between them (corners of 3, 4 and 6px, two pinks,
# three paddings); each becomes the standard. Only the button's own style
# changes: the words and the links stay as they are, including any Tim
# edited in the template editor.
class StandardEmailButtons < ActiveRecord::Migration[8.1]
  class Template < ActiveRecord::Base
    self.table_name = "content_templates"
  end

  def up
    Template.find_each do |template|
      body = EmailButton.standardize(template.body.to_s)
      next if body == template.body

      template.update_columns(body: body)
      say "#{template.key}: button restyled"
    end
  end

  def down; end
end
