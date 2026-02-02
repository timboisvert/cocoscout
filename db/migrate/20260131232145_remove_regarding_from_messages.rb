class RemoveRegardingFromMessages < ActiveRecord::Migration[8.1]
  def change
    # Migrate existing regarding data to message_regards before removing
    reversible do |dir|
      dir.up do
        # Copy existing regarding associations to message_regards
        Message.find_each do |message|
          if message.regarding_type.present? && message.regarding_id.present?
            MessageRegard.create!(
              message_id: message.id,
              regardable_type: message.regarding_type,
              regardable_id: message.regarding_id
            )
          end
        end
      end
    end

    remove_column :messages, :regarding_type, :string
    remove_column :messages, :regarding_id, :integer
  end
end
