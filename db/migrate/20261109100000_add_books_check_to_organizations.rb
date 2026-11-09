# frozen_string_literal: true

# The last result of the books' checks (BooksReconciliation), kept so every
# Books page can say how they stand without running them again: the nightly
# job and the Checks page write it.
class AddBooksCheckToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :books_check, :jsonb, default: {}, null: false
  end
end
