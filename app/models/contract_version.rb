# frozen_string_literal: true

# One version of a contract's document: the rendered text as it stood, the deal
# behind it, and the signatures collected on it.
#
# The version is the authoritative document. The counterparty's signing page and
# the PDF both read content_snapshot, never a live re-render — that's what keeps
# an amendment from silently rewriting what somebody already signed.
class ContractVersion < ApplicationRecord
  belongs_to :contract
  belongs_to :contract_template, optional: true
  belongs_to :created_by, class_name: "User", optional: true
  has_many :contract_signatures, dependent: :destroy
  has_many :contract_documents, dependent: :nullify

  validates :version_number, presence: true, uniqueness: { scope: :contract_id }
  validates :content_snapshot, presence: true

  scope :ordered, -> { order(:version_number) }

  # Derived rather than stored, so it can't drift from the contract's own state.
  def state
    return :executed if executed_at.present?
    return :out_for_signature if sent_for_signature_at.present?
    return :awaiting_send if organization_signature.present?

    :unsent
  end

  def label
    "v#{version_number}"
  end

  def superseded?
    version_number < (contract.contract_versions.maximum(:version_number) || version_number)
  end

  # Still open to being re-rendered in place — nothing has been signed or sent
  # against it yet, so repeated edits before sending don't inflate the number.
  def refreshable?
    executed_at.nil? && sent_for_signature_at.nil? && contract_signatures.none?
  end

  def organization_signature
    contract_signatures.detect(&:role_organization?)
  end

  def contractor_signature
    contract_signatures.detect(&:role_contractor?)
  end

  # A version applied as an internal correction has no signatures of its own —
  # legitimately, because nobody signed that text. It shows the last signed
  # version's signatures with a note saying so. Copying the rows forward would
  # be forging a signature over text nobody agreed to.
  def signatures_source_version
    return self if contract_signatures.any?

    contract.contract_versions.ordered
            .select { |v| v.version_number < version_number && v.contract_signatures.any? }
            .last
  end

  def effective_signatures
    signatures_source_version&.contract_signatures&.sort_by(&:signed_at) || []
  end

  def carried_forward?
    source = signatures_source_version
    source.present? && source != self
  end

  # When each nudge goes out, by window. A 7-day window gets two; 14 and 30 get
  # three. The last always lands two days before the deadline so it can say so.
  NUDGE_DAYS = { 7 => [ 3, 5 ], 14 => [ 4, 9, 12 ], 30 => [ 7, 18, 28 ] }.freeze

  def nudge_schedule
    NUDGE_DAYS[window_days] || NUDGE_DAYS[14]
  end

  def window_days
    return 14 if signature_due_at.blank? || sent_for_signature_at.blank?

    ((signature_due_at - sent_for_signature_at) / 1.day).round
  end

  def days_until_due
    return nil if signature_due_at.blank?

    ((signature_due_at - Time.current) / 1.day).ceil
  end

  def expired?
    expired_at.present?
  end

  # Waiting on the counterparty, deadline not yet passed.
  def awaiting_signature?
    sent_for_signature_at.present? && executed_at.nil? && !expired?
  end

  # Which nudge (if any) is due right now: the schedule entry we've passed that
  # we haven't sent yet.
  def due_nudge_number
    return nil unless awaiting_signature? && sent_for_signature_at.present?

    elapsed = ((Time.current - sent_for_signature_at) / 1.day).floor
    reached = nudge_schedule.count { |day| elapsed >= day }
    reached > nudge_count ? reached : nil
  end

  def pdf_document
    contract_documents.detect { |d| d.document_type == "signed_contract" && d.file.attached? }
  end
end
