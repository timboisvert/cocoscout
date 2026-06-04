# frozen_string_literal: true

# A Mic <-> User owner link. user_id is NOT NULL by design — every
# owner/co-owner/host has a CocoScout account.
class MicOwner < ApplicationRecord
  belongs_to :mic
  belongs_to :user

  enum :role, { owner: 0, co_owner: 1, host: 2 }, prefix: :role

  validates :user_id, uniqueness: { scope: :mic_id }
end
