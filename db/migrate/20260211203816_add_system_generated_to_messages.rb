class AddSystemGeneratedToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :system_generated, :boolean, default: false, null: false
  end
end
