# frozen_string_literal: true

# Books starts with its categories (Tim, 2026-11-02): a few questions about
# the organization, a recommended list to say yes to, and nothing else in
# Books until someone has. The answers stay (books_profile), the built-in
# categories the organization said no to are hidden from the pickers
# (money_categories_hidden, "income:grant" / "spending:travel"), and the
# acknowledgment is stamped.
class BooksCategoriesSetup < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :books_profile, :jsonb, default: {}, null: false
    add_column :organizations, :money_categories_hidden, :jsonb, default: [], null: false
    add_column :organizations, :books_categories_set_up_at, :datetime
    add_reference :organizations, :books_categories_set_up_by, foreign_key: { to_table: :users }
  end
end
