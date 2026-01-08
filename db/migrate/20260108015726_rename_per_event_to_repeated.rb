class RenamePerEventToRepeated < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE sign_up_forms SET scope = 'repeated' WHERE scope = 'per_event'"
  end

  def down
    execute "UPDATE sign_up_forms SET scope = 'per_event' WHERE scope = 'repeated'"
  end
end
