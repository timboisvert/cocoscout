# frozen_string_literal: true

# "Clear decided" on the casting board archives every staged decision (cast or
# rejected) so decided auditionees drop off the board, leaving only people you
# haven't decided on yet. Archiving is a soft resolve — the row stays for history
# and can be un-archived — and never sends a notification.
class AddArchivedAtToCastAssignmentStages < ActiveRecord::Migration[8.1]
  def change
    add_column :cast_assignment_stages, :archived_at, :datetime
    add_index :cast_assignment_stages, [ :audition_cycle_id, :archived_at ]
  end
end
