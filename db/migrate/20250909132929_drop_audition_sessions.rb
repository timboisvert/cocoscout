# frozen_string_literal: true

class DropAuditionSessions < ActiveRecord::Migration[8.0]
  def change
    drop_table :auditions if table_exists?(:auditions)
    return unless table_exists?(:audition_sessions)

    drop_table :audition_sessions
  end
end
