# frozen_string_literal: true

# Scopes course "sessions" (Shows with event_type "class") to a specific
# CourseOffering (run), so one Production(type: course) can hold many runs.
# Today course productions are 1:1 with an offering, so the backfill below is
# unambiguous and CourseOffering#sessions returns the identical set as before.
class AddCourseOfferingIdToShows < ActiveRecord::Migration[8.1]
  def up
    add_reference :shows, :course_offering, null: true, foreign_key: true, index: true

    # Backfill only productions that currently have exactly ONE offering (all of
    # them today), so there's no ambiguity about which run a session belongs to.
    execute <<~SQL.squish
      UPDATE shows
      SET course_offering_id = co.id
      FROM course_offerings co
      JOIN productions p ON p.id = co.production_id
      WHERE p.production_type = 'course'
        AND shows.production_id = p.id
        AND shows.course_offering_id IS NULL
        AND (SELECT COUNT(*) FROM course_offerings co2 WHERE co2.production_id = p.id) = 1
    SQL
  end

  def down
    remove_reference :shows, :course_offering, foreign_key: true
  end
end
