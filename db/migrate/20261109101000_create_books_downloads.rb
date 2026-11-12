# frozen_string_literal: true

# A spreadsheet someone asked Books for (the whole ledger, or every line of
# a period): put together in the background (BooksDownloadJob), kept in the
# private bucket for a week, and listed on Statements for whoever can see
# Books. Plus the notice that says it's ready.
class CreateBooksDownloads < ActiveRecord::Migration[8.1]
  class Template < ActiveRecord::Base
    self.table_name = "content_templates"
  end

  def up
    create_table :books_downloads do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :requested_by, foreign_key: { to_table: :users }
      t.string :kind, null: false
      t.jsonb :options, null: false, default: {}
      t.string :status, null: false, default: "pending"
      t.integer :lines_count
      t.string :error
      t.timestamps
    end
    add_index :books_downloads, %i[organization_id created_at]

    t = Template.find_or_initialize_by(key: "books_download_ready")
    t.assign_attributes(
      name: "Books download ready",
      subject: "{{download}} is ready to download",
      body: "<p>Hi {{recipient_name}},</p>" \
            "<p>{{download}} for {{organization_name}} is ready: {{lines}} lines, as a spreadsheet.</p>" \
            "<p><a href=\"{{statements_url}}\">Open Books → Statements</a> to download it. It stays there for a week.</p>",
      category: "books",
      channel: "message",
      active: true,
      available_variables: %w[recipient_name organization_name download lines statements_url]
    )
    t.save!
  end

  def down
    Template.where(key: "books_download_ready").delete_all
    drop_table :books_downloads
  end
end
