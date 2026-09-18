# frozen_string_literal: true

# The cutover: from here on, staff set their availability as time bands on the
# Work Availability page, and every reader asks StaffAvailabilityResolver.
# Carry each person's old day marks (staff_unavailabilities + the
# availability_mode flag) across one last time, so nobody's answers change
# the moment this deploys. Rows come in as `migrated`; the old table stays,
# unread and unwritten, until a later release drops it.
#
# Runs the backfill exactly once. Running it again after people have edited
# their availability would bring back what they replaced, which is why no
# rake task or controller calls it any more.
class CarryStaffAvailabilityIntoTimeBands < ActiveRecord::Migration[8.1]
  def up
    StaffAvailabilityBackfill.rebuild_all!
  end

  def down
    # Nothing to undo: the migrated rows are harmless to the old model, and
    # rolling back further (dropping the table) removes them anyway.
  end
end
