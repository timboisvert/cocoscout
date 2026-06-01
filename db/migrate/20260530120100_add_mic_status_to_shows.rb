# frozen_string_literal: true

# Adds a per-occurrence status used only by open_mic Shows. Default nil so
# every other Show type is unaffected.
#
#   scheduled            (default, treat as nil)
#   running_as_planned   (producer affirmed it's on)
#   cancelled            (producer cancelled this date specifically)
#   online_only          (moved virtual for this date)
#   extra_spots          (producer opened extra spots tonight)
class AddMicStatusToShows < ActiveRecord::Migration[8.1]
  def change
    add_column :shows, :mic_status, :integer
    add_index  :shows, :mic_status, where: "mic_status IS NOT NULL"
  end
end
