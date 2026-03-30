class ConvertBioAndPrefaceToRichText < ActiveRecord::Migration[8.1]
  def up
    # Migrate existing instructor_preface data to ActionText
    execute <<~SQL
      INSERT INTO action_text_rich_texts (name, body, record_type, record_id, created_at, updated_at)
      SELECT 'instructor_preface', instructor_preface, 'CourseOffering', id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM course_offerings
      WHERE instructor_preface IS NOT NULL AND instructor_preface != ''
    SQL

    # Migrate existing per-instructor bio data to ActionText
    execute <<~SQL
      INSERT INTO action_text_rich_texts (name, body, record_type, record_id, created_at, updated_at)
      SELECT 'bio', bio, 'CourseOfferingInstructor', id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM course_offering_instructors
      WHERE bio IS NOT NULL AND bio != ''
    SQL

    remove_column :course_offerings, :instructor_preface
    remove_column :course_offering_instructors, :bio
  end

  def down
    add_column :course_offerings, :instructor_preface, :text
    add_column :course_offering_instructors, :bio, :text
  end
end
