# frozen_string_literal: true

# Reframes "pause" from a one-off `canceled_until` date hack into a real
# state on the mic. `paused` is the explicit on/off flag (so a mic with
# no return date can still say "we're on hiatus"). `pause_note` is the
# producer's free-form message — what shows up on the public detail
# page while the mic is paused. The existing `canceled_until` is reused
# as the optional resume date: when set + paused, the regular schedule
# silently picks back up on that date.
class AddPausedStateToMics < ActiveRecord::Migration[8.1]
  def change
    add_column :mics, :paused, :boolean, default: false, null: false
    add_column :mics, :pause_note, :text
    add_index  :mics, :paused
  end
end
