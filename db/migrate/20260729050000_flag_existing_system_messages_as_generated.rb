# frozen_string_literal: true

# Automated "system"-type notifications (contract signing requests, casting-table
# alerts, etc.) were being created with system_generated: false, so they rendered
# as coming from whichever user technically sent them. Going forward the delivery
# path flags them correctly; this aligns the existing rows so they're attributed
# as automated notifications too.
class FlagExistingSystemMessagesAsGenerated < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE messages
      SET system_generated = true
      WHERE message_type = 'system'
        AND system_generated = false
    SQL
  end

  def down
    # No-op: we can't tell which rows were flipped, and leaving them flagged is
    # the correct state anyway.
  end
end
