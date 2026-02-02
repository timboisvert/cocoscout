class AddThreadingToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :parent_message_id, :integer
    add_column :messages, :sent_on_behalf_of_type, :string
    add_column :messages, :sent_on_behalf_of_id, :integer

    add_index :messages, :parent_message_id
    add_index :messages, [ :sent_on_behalf_of_type, :sent_on_behalf_of_id ], name: "index_messages_on_sent_on_behalf_of"
  end
end
