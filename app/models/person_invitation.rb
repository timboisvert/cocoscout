# frozen_string_literal: true

class PersonInvitation < ApplicationRecord
  belongs_to :organization, optional: true
  belongs_to :talent_pool, optional: true

  normalizes :email, with: ->(e) { e.strip.downcase }

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP, message: "must be a valid email address" }
  validates :token, presence: true, uniqueness: true

  before_validation :generate_token, on: :create

  scope :pending, -> { where(accepted_at: nil, declined_at: nil) }

  def generate_token
    self.token ||= SecureRandom.hex(20)
  end

  def pending?
    accepted_at.nil? && declined_at.nil?
  end
end
