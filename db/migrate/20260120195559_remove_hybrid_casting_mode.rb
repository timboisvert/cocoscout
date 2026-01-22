class RemoveHybridCastingMode < ActiveRecord::Migration[8.1]
  def up
    # Convert all productions using 'hybrid' casting mode to 'talent_pool'
    # Talent pool now supports the same click-to-add functionality
    execute <<-SQL
      UPDATE productions SET casting_source = 'talent_pool' WHERE casting_source = 'hybrid'
    SQL

    # Convert all shows using 'hybrid' casting mode to 'talent_pool'
    execute <<-SQL
      UPDATE shows SET casting_source = 'talent_pool' WHERE casting_source = 'hybrid'
    SQL
  end

  def down
    # No-op: We can't know which ones were originally hybrid
  end
end
