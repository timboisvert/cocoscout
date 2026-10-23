# frozen_string_literal: true

# An address no organization on CocoScout emails again: it bounced for good or
# its owner marked an email as spam. Protects CocoScout's sending reputation.
class EmailSuppression < ApplicationRecord
  REASONS = %w[bounced complained].freeze

  normalizes :email, with: ->(email) { email.to_s.strip.downcase }

  validates :email, presence: true, uniqueness: true
  validates :reason, inclusion: { in: REASONS }

  def self.suppressed?(email)
    exists?(email: email.to_s.strip.downcase)
  end

  def self.suppress!(email, reason:, source: nil)
    create!(email: email, reason: reason, source: source)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    find_by(email: email.to_s.strip.downcase)
  end
end
