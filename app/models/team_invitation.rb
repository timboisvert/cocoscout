# frozen_string_literal: true

class TeamInvitation < ApplicationRecord
  belongs_to :organization
  belongs_to :production, optional: true
  belongs_to :person, optional: true

  normalizes :email, with: ->(e) { e.strip.downcase }

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP, message: "must be a valid email address" }
  validates :token, presence: true, uniqueness: true
  validate :production_belongs_to_organization

  before_validation :generate_token, on: :create

  def generate_token
    self.token ||= SecureRandom.hex(20)
  end

  def production_invite?
    production_id.present?
  end

  private

  def production_belongs_to_organization
    return unless production_id.present? && organization_id.present?
    unless production.organization_id == organization_id
      errors.add(:production, "must belong to the same organization")
    end
  end
end
