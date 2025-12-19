class RemoveUniqueIndexFromPersonEmail < ActiveRecord::Migration[8.1]
  def change
    remove_index :people, :email, unique: true
    add_index :people, :email  # Keep a non-unique index for lookup performance
  end
end
