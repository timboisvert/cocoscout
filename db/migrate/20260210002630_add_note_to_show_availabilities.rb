class AddNoteToShowAvailabilities < ActiveRecord::Migration[8.1]
  def change
    add_column :show_availabilities, :note, :string
  end
end
