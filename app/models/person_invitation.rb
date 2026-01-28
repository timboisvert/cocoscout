# frozen_string_literal: true

class PersonInvitation < ApplicationRecord
  belongs_to :organization, optional: true
  belongs_to :talent_pool, optional: true

  validates :email, presence: true
  validates :token, presence: true, uniqueness: true

  before_validation :generate_token, on: :create

  scope :pending, -> { where(accepted_at: nil, declined_at: nil) }
  scope :for_talent_pool, ->(talent_pool) { where(talent_pool: talent_pool) }

  def generate_token
    self.token ||= SecureRandom.hex(20)
  end

  def pending?
    accepted_at.nil? && declined_at.nil?
  end
end
