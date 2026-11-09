# frozen_string_literal: true

# A spreadsheet Books was asked for: the whole ledger, or every line of a
# period. Asking makes the row and starts BooksDownloadJob, which writes the
# file to the private bucket; the Statements page lists the last week's for
# anyone who can see Books, and the person who asked is told when it's
# ready. Nothing heavy runs in the page request (Tim, 2026-11-09).
class BooksDownload < ApplicationRecord
  KINDS = %w[ledger period].freeze
  KEPT_FOR = 7.days
  ASKED = "It's being put together and will be listed under For your accountant; you'll get a notification when it's ready."

  belongs_to :organization
  belongs_to :requested_by, class_name: "User", optional: true
  has_one_attached :file

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: %w[pending ready failed] }

  scope :recent, -> { where(created_at: KEPT_FOR.ago..).order(created_at: :desc) }

  # Asking twice in a few minutes for the same thing gets the one already
  # being put together.
  def self.ask!(organization:, by:, kind:, options: {})
    options = options.compact.transform_keys(&:to_s).transform_values(&:to_s)
    waiting = organization.books_downloads.where(kind: kind, status: "pending", created_at: 10.minutes.ago..).find { |d| d.options == options }
    return waiting if waiting

    organization.books_downloads.create!(requested_by: by, kind: kind, options: options).tap { |download| BooksDownloadJob.perform_later(download.id) }
  end

  def pending? = status == "pending"
  def ready? = status == "ready" && file.attached?
  def failed? = status == "failed"

  def basis = options["basis"] == "cash" ? :cash : :accrual
  def period = options["period"].presence_in(BooksReport::PERIODS.keys) || "this_month"

  def title
    return "The whole ledger" if kind == "ledger"

    "Every line, #{period.humanize.downcase}, #{basis == :cash ? 'when it moved' : 'when it was earned'}"
  end

  def filename
    stamp = created_at.to_date.iso8601
    kind == "ledger" ? "#{organization.name.parameterize}-ledger-#{stamp}.csv" : "books-#{period.tr('_', '-')}-#{basis == :cash ? 'when-moved' : 'when-earned'}-#{stamp}.csv"
  end

  # Writes the spreadsheet to io; answers how many lines.
  def write(io)
    if kind == "ledger"
      BooksStatements.new(organization).write_ledger_csv(io)
    else
      production_id = organization.productions.find_by(id: options["production"])&.id
      BooksReport.new(organization, basis: basis).write_csv(io, range: BooksReport.period_range(period), production_id: production_id)
    end
  end
end
