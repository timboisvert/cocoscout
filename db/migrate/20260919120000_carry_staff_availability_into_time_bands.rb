# frozen_string_literal: true

# The cutover: from here on, staff set their availability as time bands on the
# Work Availability page, and every reader asks StaffAvailabilityResolver.
# Carry each person's old day marks (staff_unavailabilities + the
# availability_mode flag) across one last time, so nobody's answers change
# the moment this deploys. Rows come in as `migrated`; the old table stays,
# unread and unwritten, until a later release drops it.
#
# Ran the backfill exactly once (production, 2026-09-29). Running it again
# after people had edited their availability would have brought back what
# they replaced, so the backfill code is gone (2026-10-03, with the old
# table: DropStaffUnavailabilities) and this migration is now a no-op for any
# database built from scratch, which loads the schema anyway.
class CarryStaffAvailabilityIntoTimeBands < ActiveRecord::Migration[8.1]
  def up
    # The one-time carry-over already happened everywhere it was going to.
  end

  def down
    # Nothing to undo: the migrated rows are harmless to the old model, and
    # rolling back further (dropping the table) removes them anyway.
  end
end
