class RemoveKeyFromquestion < ActiveRecord::Migration[8.0]
  def change
    remove_column :questions, :key
  end
end
