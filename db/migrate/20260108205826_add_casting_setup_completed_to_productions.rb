class AddCastingSetupCompletedToProductions < ActiveRecord::Migration[8.1]
  def change
    add_column :productions, :casting_setup_completed, :boolean, default: false, null: false

    # Mark all existing productions as having completed setup (they already have data)
    execute "UPDATE productions SET casting_setup_completed = true"
  end
end
