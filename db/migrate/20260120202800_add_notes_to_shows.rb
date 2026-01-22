class AddNotesToShows < ActiveRecord::Migration[8.1]
  def change
    add_column :shows, :notes, :text
  end
end
