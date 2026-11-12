# frozen_string_literal: true

# The words of the nightly books check's notification to CocoScout's
# superadmins (BooksNotices.books_disagree). Its own migration because
# 20261109140000 had already run where the rest of BooksTemplates was seeded.
class SeedBooksCheckMismatchTemplate < ActiveRecord::Migration[8.1]
  def up
    BooksTemplates.ensure!(keys: %w[books_check_mismatch])
  end

  def down
    ContentTemplate.where(key: "books_check_mismatch").delete_all
  end
end
