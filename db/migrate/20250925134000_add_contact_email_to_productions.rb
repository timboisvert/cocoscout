class AddContactEmailToProductions < ActiveRecord::Migration[7.0]
  def change
    add_column :productions, :contact_email, :string
  end
end
