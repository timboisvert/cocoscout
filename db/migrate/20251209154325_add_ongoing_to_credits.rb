class AddOngoingToCredits < ActiveRecord::Migration[8.1]
  def change
    add_column :performance_credits, :ongoing, :boolean, default: false, null: false
    add_column :training_credits, :ongoing, :boolean, default: false, null: false
  end
end
