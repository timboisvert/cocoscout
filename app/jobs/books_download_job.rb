# frozen_string_literal: true

# Puts a Books spreadsheet together (BooksDownload): written a batch at a
# time to a file on disk, stored under the organization's folder in the
# private bucket, then whoever asked is told. Downloads older than a week
# are removed on the way out.
class BooksDownloadJob < ApplicationJob
  queue_as :default

  def perform(download_id)
    download = BooksDownload.find_by(id: download_id)
    return unless download&.pending?

    organization = download.organization
    Tempfile.create([ "books-download", ".csv" ], encoding: "UTF-8") do |file|
      lines = download.write(file)
      file.rewind
      download.file.attach(io: file, filename: download.filename, content_type: "text/csv",
                           key: "organizations/#{organization.id}/books_downloads/#{download.id}/#{SecureRandom.hex(12)}.csv")
      download.update!(status: "ready", lines_count: lines, error: nil)
    end
    notify(download)
    organization.books_downloads.where(created_at: ...BooksDownload::KEPT_FOR.ago).find_each(&:destroy!)
  rescue StandardError => e
    download&.update_columns(status: "failed", error: e.message.truncate(255), updated_at: Time.current)
    raise
  end

  private

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
