# frozen_string_literal: true

# A Mic <-> User producer link. user_id is NOT NULL by design — every
# producer/co-producer/host has a CocoScout account.
class MicProducer < ApplicationRecord
  belongs_to :mic
  belongs_to :user

  enum :role, { producer: 0, co_producer: 1, host: 2 }, prefix: :role

  validates :user_id, uniqueness: { scope: :mic_id }
end
