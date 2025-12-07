class AddUpcomingEventsModeToProductions < ActiveRecord::Migration[8.1]
  def change
    add_column :productions, :show_upcoming_events_mode, :string, default: "all"
    add_column :productions, :show_upcoming_event_types, :text
  end
end
