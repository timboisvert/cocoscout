class AddAvailabilityFieldsToCallToAuditions < ActiveRecord::Migration[8.1]
  def change
    add_column :auditions, :include_availability_section, :boolean, default: false
    add_column :auditions, :availability_event_types, :text
  end
end
