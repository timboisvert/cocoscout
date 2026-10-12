# frozen_string_literal: true

class DeviceToken < ApplicationRecord
  belongs_to :user
  belongs_to :app_session, optional: true

  validates :token, presence: true
  validates :platform, presence: true, inclusion: { in: %w[ios android] }
  validates :token, uniqueness: { scope: :platform }
end
