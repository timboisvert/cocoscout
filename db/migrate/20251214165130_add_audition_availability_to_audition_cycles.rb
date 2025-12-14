class AddAuditionAvailabilityToAuditionCycles < ActiveRecord::Migration[8.1]
  def change
    add_column :audition_cycles, :include_audition_availability_section, :boolean, default: false
    add_column :audition_cycles, :require_all_audition_availability, :boolean, default: false
  end
end
