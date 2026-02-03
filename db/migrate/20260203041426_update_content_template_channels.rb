# frozen_string_literal: true

class UpdateContentTemplateChannels < ActiveRecord::Migration[8.0]
  def up
    # casting_table_notification should be message, not email
    execute <<~SQL
      UPDATE content_templates SET channel = 'message'
      WHERE key = 'casting_table_notification'
    SQL

    # vacancy_invitation, vacancy_invitation_linked, and show_canceled should be both
    execute <<~SQL
      UPDATE content_templates SET channel = 'both'
      WHERE key IN ('vacancy_invitation', 'vacancy_invitation_linked', 'show_canceled')
    SQL
  end

  def down
    execute <<~SQL
      UPDATE content_templates SET channel = 'email'
      WHERE key = 'casting_table_notification'
    SQL

    execute <<~SQL
      UPDATE content_templates SET channel = 'email'
      WHERE key IN ('vacancy_invitation', 'vacancy_invitation_linked')
    SQL

    execute <<~SQL
      UPDATE content_templates SET channel = 'message'
      WHERE key = 'show_canceled'
    SQL
  end
end
