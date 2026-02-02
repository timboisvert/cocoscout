class AddDeletedAtToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :deleted_at, :datetime
  end
end
