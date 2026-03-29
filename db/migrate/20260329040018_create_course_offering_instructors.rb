class CreateCourseOfferingInstructors < ActiveRecord::Migration[8.1]
  def change
    create_table :course_offering_instructors do |t|
      t.references :course_offering, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.integer :position, default: 0, null: false
      t.timestamps
    end

    add_index :course_offering_instructors, [ :course_offering_id, :person_id ], unique: true,
              name: "idx_course_offering_instructors_unique"

    # Migrate existing single-instructor data to the join table
    reversible do |dir|
      dir.up do
        execute <<-SQL
          INSERT INTO course_offering_instructors (course_offering_id, person_id, position, created_at, updated_at)
          SELECT id, instructor_person_id, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
          FROM course_offerings
          WHERE instructor_person_id IS NOT NULL
        SQL
      end
    end
  end
end
