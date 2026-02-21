class AddAcceptanceFieldsToAuditions < ActiveRecord::Migration[8.1]
  def change
    add_column :auditions, :accepted_at, :datetime
    add_column :auditions, :declined_at, :datetime
  end
end
