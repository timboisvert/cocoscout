# frozen_string_literal: true

# Puts a Books spreadsheet together (BooksDownload): written a batch at a
# time to a file on disk, stored under the organization's folder in the
# private bucket, then whoever asked is told: it's ready, or it couldn't be
# made (they were promised a notification either way; Tim, 2026-11-09).
# Downloads older than a week are removed on the way out. Telling them and
# the clearing out are outside the rescue, so neither can turn a download
# that was made into one that failed.
class BooksDownloadJob < ApplicationJob
  queue_as :default

  def perform(download_id)
    download = BooksDownload.find_by(id: download_id)
    return unless download&.pending?

    build(download)
    notify(download)
    download.organization.books_downloads.where(created_at: ...BooksDownload::KEPT_FOR.ago).find_each(&:destroy!)
  end

  private

  def build(download)
    organization = download.organization
    Tempfile.create([ "books-download", ".csv" ], encoding: "UTF-8") do |file|
      lines = download.write(file)
      file.rewind
      download.file.attach(io: file, filename: download.filename, content_type: "text/csv",
                           key: "organizations/#{organization.id}/books_downloads/#{download.id}/#{SecureRandom.hex(12)}.csv")
      download.update!(status: "ready", lines_count: lines, error: nil)
    end
  rescue StandardError => e
    download.update_columns(status: "failed", error: e.message.truncate(255), updated_at: Time.current)
    urls = Rails.application.routes.url_helpers
    BooksNotices.failed("books_download_failed", user: download.requested_by, organization: download.organization, subject: download,
                        path: urls.manage_money_statements_path, download: download.title, statements_url: urls.manage_money_statements_url(**url_options))
    raise
  end

  def notify(download)
    user = download.requested_by
    return unless user

    urls = Rails.application.routes.url_helpers
    Notifier.deliver(
      user: user, category: "books", kind: "books_download_ready", template_key: "books_download_ready",
      variables: { recipient_name: (user.person&.name.presence || "there"), organization_name: download.organization.name, download: download.title,
                   lines: download.lines_count, statements_url: urls.manage_money_statements_url(**url_options) },
      path: urls.manage_money_statements_path, organization: download.organization, subject: download
    )
  end

  def url_options
    Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
  end
end
