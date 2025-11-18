class AddAvailabilityShowIdsToAuditionCycles < ActiveRecord::Migration[8.1]
  def change
    add_column :audition_cycles, :availability_show_ids, :text
  end
end
