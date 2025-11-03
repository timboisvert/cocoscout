class AddAvailabilityFieldsToCallToAuditionsCorrectTable < ActiveRecord::Migration[8.1]
  def change
    add_column :call_to_auditions, :include_availability_section, :boolean, default: false
    add_column :call_to_auditions, :availability_event_types, :text
  end
end
