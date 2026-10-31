# frozen_string_literal: true

# Books V1.3, plan E2: the books can be locked through a date (a closed
# month); and E1: nonprofit words on the statements when the organization
# says it is one.
class AddBooksLockToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :books_locked_through, :date
    add_column :organizations, :books_locked_at, :datetime
    add_reference :organizations, :books_locked_by, foreign_key: { to_table: :users }
    add_column :organizations, :books_nonprofit, :boolean, null: false, default: false
  end
end
