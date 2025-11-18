class RemoveAvailabilityEventTypesFromAuditionCycles < ActiveRecord::Migration[8.1]
  def change
    remove_column :audition_cycles, :availability_event_types, :text
  end
end
