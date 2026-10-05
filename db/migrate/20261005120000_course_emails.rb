# frozen_string_literal: true

# The words of every email a student gets about a course (CourseTemplates):
# the confirmation rewritten around the when-and-where block and the
# receipt, plus refund, removal, session changed, session canceled and the
# reminder. Overwrites the old confirmation words.
class CourseEmails < ActiveRecord::Migration[8.1]
  def up
    CourseTemplates.ensure!(overwrite: true)
  end

  def down
    ContentTemplate.where(key: CourseTemplates::TEMPLATES.map { |t| t[:key] } - [ "course_registration_confirmed" ]).delete_all
  end
end
