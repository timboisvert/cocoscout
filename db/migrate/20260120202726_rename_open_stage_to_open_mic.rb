class RenameOpenStageToOpenMic < ActiveRecord::Migration[8.1]
  def change
    # Update any shows with event_type 'open_stage' to 'open_mic'
    reversible do |dir|
      dir.up do
        execute "UPDATE shows SET event_type = 'open_mic' WHERE event_type = 'open_stage'"
      end
      dir.down do
        execute "UPDATE shows SET event_type = 'open_stage' WHERE event_type = 'open_mic'"
      end
    end
  end
end
