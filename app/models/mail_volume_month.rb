# frozen_string_literal: true

# One month's count of every email CocoScout sent (MailVolume).
class MailVolumeMonth < ApplicationRecord
  validates :month, presence: true, uniqueness: true
end
