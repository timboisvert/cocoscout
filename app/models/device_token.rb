# frozen_string_literal: true

class DeviceToken < ApplicationRecord
  belongs_to :user

  validates :token, presence: true
  validates :platform, presence: true, inclusion: { in: %w[ios android] }
  validates :token, uniqueness: { scope: :platform }
end
