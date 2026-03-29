class AddListedInDirectoryToAuditionCycles < ActiveRecord::Migration[8.1]
  def change
    add_column :audition_cycles, :listed_in_directory, :boolean, default: true, null: false
  end
end
