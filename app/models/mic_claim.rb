# frozen_string_literal: true

# A producer's attempt to claim a Mic. Once approved, we insert a
# corresponding `MicProducer` row.
class MicClaim < ApplicationRecord
  belongs_to :mic
  belongs_to :claimant, class_name: "User", foreign_key: :claimant_user_id
  belongs_to :adjudicator, class_name: "User", foreign_key: :adjudicator_user_id, optional: true

  enum :status, { pending: 0, approved: 1, rejected: 2 }, prefix: :status
  enum :role,   { producer: 0, co_producer: 1 }, prefix: :role
end
