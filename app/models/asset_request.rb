# frozen_string_literal: true

# The one link that asks someone outside for a production's images and
# words (Tim, 2026-11-19). Anyone holding it can upload, so it can be passed
# to a designer. It stays open until the production's last date has passed,
# with nothing to set; a manager can turn it off or make a new link, which
# ends this one. People on the contract who have an account get the same
# page on My Contracts without the link.
class AssetRequest < ApplicationRecord
  belongs_to :production
  belongs_to :created_by, class_name: "User", optional: true
  has_many :production_assets, dependent: :nullify

  scope :live, -> { where(turned_off_at: nil) }

  before_validation :mint_token, on: :create
  validates :token, presence: true, uniqueness: true

  # The production's request whose link still works, if any.
  def self.current_for(production)
    production.asset_requests.live.order(created_at: :desc).first
  end

  # The email's subject when the manager writes none, and what the request
  # sheet starts with (Tim, 2026-11-19: "needed for", not "we need for").
  def self.default_subject(production) = "Images and details needed for #{production.name}"

  # The email's words when the manager writes none, and what the request
  # sheet starts with: plain and businesslike, no greeting (Tim, 2026-11-19).
  def self.default_message(production)
    organization = production.organization.name
    "#{organization} requests the visual assets and written details listed below for #{production.name}. " \
      "Each image is listed with its required size and file types.\n\n" \
      "Upload them at the link below. You can add them a few at a time, and the link works until the production's last date."
  end

  def turned_off? = turned_off_at.present?

  # Open until it's turned off or the production's last date has passed. A
  # production with no dates yet is open; adding a date opens it again.
  def open?
    !turned_off? && !production_over?
  end

  def production_over?
    last = production.shows.maximum(:date_and_time)
    last.present? && last < Time.current.beginning_of_day
  end

  def last_date
    production.shows.maximum(:date_and_time)
  end

  def turn_off!
    update!(turned_off_at: Time.current)
  end

  def recipient_emails = Array(recipients).map(&:to_s).compact_blank

  def url
    Rails.application.routes.url_helpers.asset_request_url(token: token, **(Rails.application.config.action_mailer.default_url_options || {}))
  end

  # Someone outside changed something: the managers hear about it in one
  # notification a little later, not one per file.
  def note_activity!
    update_column(:last_activity_at, Time.current)
    AssetRequestActivityJob.set(wait: AssetRequestActivityJob::WAIT).perform_later(id)
  end

  private

  def mint_token
    self.token ||= SecureRandom.urlsafe_base64(24)
  end
end
