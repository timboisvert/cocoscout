class AddAutoCreateEventPagesToProductions < ActiveRecord::Migration[8.1]
  def change
    add_column :productions, :auto_create_event_pages, :boolean, default: true
    add_column :productions, :auto_create_event_pages_mode, :string, default: "all"
  end
end
