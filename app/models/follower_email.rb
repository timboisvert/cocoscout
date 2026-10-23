# frozen_string_literal: true

# An email to followers ("Emails" on Mailing lists, V1.1): the manager's own
# words (an ActionText body), shows drawn as blocks after them, sent to lists
# and segments. Draft until sent; then each follower's copy is a
# FollowerEmailDelivery.
class FollowerEmail < ApplicationRecord
  STATUSES = %w[draft sending sent].freeze

  belongs_to :organization
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :sent_by, class_name: "User", optional: true
  has_many :follower_email_deliveries, dependent: :destroy
  has_rich_text :body

  validates :status, inclusion: { in: STATUSES }

  scope :drafts, -> { where(status: "draft").order(updated_at: :desc) }
  scope :sent_or_sending, -> { where(status: %w[sending sent]).order(sent_at: :desc) }

  def draft? = status == "draft"
  def sent? = status == "sent"

  def list_ids = Array(targets["list_ids"]).map(&:to_i).uniq
  def segment_ids = Array(targets["segment_ids"]).map(&:to_i).uniq

  def lists
    organization.mailing_lists.where(id: list_ids)
  end

  def segments
    organization.segments.where(id: segment_ids)
  end

  # The shows drawn as blocks, in the order they were added; only this
  # organization's.
  def shows
    ids = Array(show_ids).map(&:to_i)
    found = Show.joins(:production).where(productions: { organization_id: organization_id }, id: ids).includes(:production).index_by(&:id)
    ids.filter_map { |id| found[id] }
  end

  def audience
    FollowerAudience.new(self)
  end

  # The utm campaign its links carry, so a ticket sold from it counts here.
  def campaign_key = "fe-#{id}"

  def ticket_orders
    organization.ticket_orders.where(status: "paid").where("ticket_orders.utm ->> 'campaign' = ?", campaign_key)
  end

  def counts
    @counts ||= follower_email_deliveries.group(:status).count
  end
end
