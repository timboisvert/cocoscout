# frozen_string_literal: true

# A show may override its production's casting style (roles vs acts), the
# same way it may override casting_source. nil means "inherit".
class AddCastingModeToShows < ActiveRecord::Migration[8.0]
  def change
    add_column :shows, :casting_mode, :string
    add_index :shows, :casting_mode
  end
end
