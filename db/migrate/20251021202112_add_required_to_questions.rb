class AddRequiredToQuestions < ActiveRecord::Migration[8.0]
  def change
    add_column :questions, :required, :boolean, default: false, null: false
  end
end
