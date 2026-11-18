# frozen_string_literal: true

# A block of extra emails to followers that an organization bought (Tim,
# 2026-11-17): 1,000 for $3, bought on the send screen when an email would
# go past what's left. It goes on the organization's next monthly bill as
# its own line (UsageInvoiceCorrection), never charged by itself. What it
# paid for doesn't expire while the organization is on Pro
# (FollowerEmailAllowance).
class FollowerEmailBlock < ApplicationRecord
  EMAILS = 1_000
  PRICE_CENTS = 300

  belongs_to :organization
  belongs_to :bought_by, class_name: "User", optional: true
  belongs_to :follower_email, optional: true

  validates :emails, :price_cents, numericality: { greater_than: 0 }

  before_validation { self.emails ||= EMAILS; self.price_cents ||= PRICE_CENTS }

  # CocoScout's superadmins hear about each one (SuperadminNotices).
  after_create_commit { SuperadminNotices.follower_email_block_bought(self) }

  scope :bought_in, ->(month) { where(created_at: month.beginning_of_month.beginning_of_day..month.end_of_month.end_of_day) }

  def self.price_words = ActiveSupport::NumberHelper.number_to_currency(PRICE_CENTS / 100.0, precision: 0)
end
