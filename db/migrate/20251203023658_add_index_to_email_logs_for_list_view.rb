# frozen_string_literal: true

class AddIndexToEmailLogsForListView < ActiveRecord::Migration[8.1]
  def change
    # Composite index for the common query pattern: ORDER BY sent_at DESC with user_id filter
    # The existing sent_at index doesn't help with DESC ordering in PostgreSQL
    add_index :email_logs, %i[sent_at user_id], order: { sent_at: :desc },
                                                name: 'index_email_logs_on_sent_at_desc_user_id'
  end
end
