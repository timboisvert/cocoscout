# frozen_string_literal: true

class TeamInvitation < ApplicationRecord
  belongs_to :organization
  belongs_to :production, optional: true
  belongs_to :person, optional: true

  validates :email, presence: true
  validates :token, presence: true, uniqueness: true
  validate :production_belongs_to_organization

  before_validation :generate_token, on: :create

  def generate_token
    self.token ||= SecureRandom.hex(20)
  end

  def production_invite?
    production_id.present?
  end

  def organization_invite?
    production_id.blank?
  end

  private

  def production_belongs_to_organization
    return unless production_id.present? && organization_id.present?
    unless production.organization_id == organization_id
      errors.add(:production, "must belong to the same organization")
    end
  end
end
