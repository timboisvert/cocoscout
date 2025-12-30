class AddAuditionFormatColumnsToAuditionCycles < ActiveRecord::Migration[8.1]
  def up
    add_column :audition_cycles, :allow_video_submissions, :boolean, default: false, null: false
    add_column :audition_cycles, :allow_in_person_auditions, :boolean, default: false, null: false

    # Migrate existing data from audition_type enum
    execute <<-SQL
      UPDATE audition_cycles
      SET allow_video_submissions = (audition_type = 'video_upload'),
          allow_in_person_auditions = (audition_type = 'in_person')
    SQL
  end

  def down
    remove_column :audition_cycles, :allow_video_submissions
    remove_column :audition_cycles, :allow_in_person_auditions
  end
end
