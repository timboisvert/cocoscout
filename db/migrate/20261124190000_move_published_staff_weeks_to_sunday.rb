# frozen_string_literal: true

# The staff schedule's week runs Sunday through Saturday (Tim, 2026-11-24;
# it ran Monday to Sunday). A published week is stored by its first day, so
# each one moves from its Monday to the Sunday before: Monday to Saturday
# stay in the same published week, and each Sunday now goes with the week it
# starts. Plain SQL, so it reads no app code.
#
# One thing changes for a Sunday that was published while the week after it
# was not: it is a draft again until that week is published (on the
# 2026-11-22 production copy, one day: Sunday, December 6, 2026 at Stars &
# Garters). The reverse makes a Sunday published with the week it starts.
class MovePublishedStaffWeeksToSunday < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE staffing_finalizations SET week_start = week_start - 1 WHERE EXTRACT(DOW FROM week_start) = 1"
  end

  def down
    execute "UPDATE staffing_finalizations SET week_start = week_start + 1 WHERE EXTRACT(DOW FROM week_start) = 0"
  end
end
