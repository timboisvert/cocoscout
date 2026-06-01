# frozen_string_literal: true

# Producers can now turn off the resume requirement on an audition cycle.
# Default to true so existing cycles keep prompting performers to upload
# a resume, matching their behavior before this column existed.
class AddResumeRequiredToAuditionCycles < ActiveRecord::Migration[8.1]
  def change
    add_column :audition_cycles, :resume_required, :boolean, null: false, default: true
  end
end
