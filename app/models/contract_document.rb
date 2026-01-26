# frozen_string_literal: true

class ContractDocument < ApplicationRecord
  belongs_to :contract

  has_one_attached :file

  # Document types
  DOCUMENT_TYPES = %w[
    signed_contract
    unsigned_contract
    rider
    insurance_certificate
    invoice
    receipt
    other
  ].freeze

  validates :name, presence: true
  validates :document_type, inclusion: { in: DOCUMENT_TYPES }, allow_blank: true

  scope :by_type, ->(type) { where(document_type: type) }
  scope :recent, -> { order(created_at: :desc) }

  def signed_contract?
    document_type == "signed_contract"
  end

  def invoice?
    document_type == "invoice"
  end
end
