# frozen_string_literal: true

class FeatureCredit < ApplicationRecord
  has_many :feature_credit_redemptions, dependent: :restrict_with_error

  validates :code, presence: true, uniqueness: { case_sensitive: false }
  validates :feature_type, presence: true, inclusion: { in: %w[courses ticketing] }
  validates :scope_type, presence: true, inclusion: { in: %w[course_offering production organization] }
  validates :max_uses, numericality: { greater_than: 0 }, allow_nil: true

  before_validation :normalize_code

  scope :active_codes, -> { where(active: true) }
  scope :for_feature, ->(feature) { where(feature_type: feature) }

  def self.find_by_normalized_code(code)
    return nil if code.blank?
    find_by(code: code.strip.upcase)
  end

  def redeemable?
    active? &&
      !expired? &&
      !maxed_out?
  end

  def expired?
    expires_at.present? && Time.current > expires_at
  end

  def maxed_out?
    max_uses.present? && uses_count >= max_uses
  end

  def redeem!(organization:, redeemable:)
    raise "Code is not redeemable" unless redeemable?

    transaction do
      redemption = feature_credit_redemptions.create!(
        organization: organization,
        redeemable: redeemable
      )
      increment!(:uses_count)
      redemption
    end
  end

  private

  def normalize_code
    self.code = code&.strip&.upcase
  end
end
