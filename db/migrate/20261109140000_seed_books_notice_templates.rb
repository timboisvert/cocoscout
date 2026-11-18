# frozen_string_literal: true

# The words of the Books notices added on 2026-11-09 (BooksTemplates): an
# invoice paid on its page, and a statement's matching, a run of bank rules
# or a download that didn't finish.
class SeedBooksNoticeTemplates < ActiveRecord::Migration[8.1]
  def up
    BooksTemplates.ensure!
  end

  def down
    ContentTemplate.where(key: BooksTemplates::TEMPLATES.map { |t| t[:key] }).delete_all
  end
end
