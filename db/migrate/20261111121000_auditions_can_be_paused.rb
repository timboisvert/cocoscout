# frozen_string_literal: true

# Pausing auditions (Tim, 2026-11-11): an open-ended cycle has no end date to
# set, so it's paused instead, and stays open-ended. Nobody new can send a
# request while it's paused; resuming changes nothing else.
class AuditionsCanBePaused < ActiveRecord::Migration[8.1]
  def change
    add_column :audition_cycles, :paused_at, :datetime
  end
end
