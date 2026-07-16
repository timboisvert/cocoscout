# frozen_string_literal: true

# AgreementRequest records that a production asked a person to sign its
# agreement. Paired with AgreementSignature (which records that they *did*), it
# gives the producer a clear roster: not-sent → awaiting → signed.
#
# One row per (production, person). Re-sending bumps sent_at and send_count
# rather than creating duplicates (see .record!).
class AgreementRequest < ApplicationRecord
  belongs_to :production
  belongs_to :person
  belongs_to :agreement_template, optional: true
  belongs_to :sent_by, class_name: "User", optional: true

  validates :sent_at, presence: true
  validates :person_id, uniqueness: { scope: :production_id }

  scope :for_production, ->(production) { where(production: production) }

  # Idempotent record of "we asked this person". Creates the row on first send,
  # bumps sent_at / send_count on re-sends.
  def self.record!(production:, person:, via: "manual", sent_by: nil)
    request = find_or_initialize_by(production: production, person: person)
    request.agreement_template = production.agreement_template
    request.sent_by = sent_by if sent_by
    request.sent_via = via
    request.sent_at = Time.current
    request.send_count = request.persisted? ? request.send_count + 1 : 1
    request.save!
    request
  end
end
