# frozen_string_literal: true

class EmailLog < ApplicationRecord
  belongs_to :user
  belongs_to :recipient_entity, polymorphic: true, optional: true
  belongs_to :email_batch, optional: true
  belongs_to :organization, optional: true

  # Store email body as an Active Storage attachment (HTML file in S3)
  has_one_attached :body_file

  validates :recipient, presence: true

  scope :sent, -> { where.not(sent_at: nil) }
  scope :delivered, -> { where(delivery_status: "delivered") }
  scope :failed, -> { where(delivery_status: "failed") }
  scope :for_user, ->(user) { where(user: user) }
  scope :for_recipient_entity, ->(entity) { where(recipient_entity: entity) }
  scope :for_organization, ->(org) { where(organization: org) }
  scope :recent, -> { order(sent_at: :desc) }

  # Helper to get body content (from Active Storage or legacy column)
  def body_content
    if body_file.attached?
      body_file.download
    elsif respond_to?(:body) && body.present?
      body # Legacy column, if still exists
    end
  end

  # Helper to set body content (saves to Active Storage)
  def body_content=(html_content)
    return if html_content.blank?

    body_file.attach(
      io: StringIO.new(html_content),
      filename: "email_#{id || SecureRandom.hex(8)}.html",
      content_type: "text/html"
    )
  end

  def delivered?
    delivery_status == "delivered"
  end

  def failed?
    delivery_status == "failed"
  end

  def pending?
    delivery_status == "pending"
  end
end
