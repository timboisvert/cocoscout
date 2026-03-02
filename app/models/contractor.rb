# frozen_string_literal: true

class Contractor < ApplicationRecord
  belongs_to :organization
  has_many :contracts, dependent: :nullify

  validates :name, presence: true
  validates :name, uniqueness: { scope: :organization_id, case_sensitive: false }

  scope :alphabetical, -> { order(:name) }
  scope :with_contracts, -> { joins(:contracts).distinct }
  scope :with_active_contracts, -> { joins(:contracts).where(contracts: { status: "active" }).distinct }

  def active_contracts
    contracts.status_active
  end

  def completed_contracts
    contracts.status_completed.or(contracts.status_cancelled)
  end

  def total_contracts_count
    contracts.count
  end

  def display_email
    email.presence || contracts.where.not(contractor_email: [ nil, "" ]).pick(:contractor_email)
  end

  def display_phone
    phone.presence || contracts.where.not(contractor_phone: [ nil, "" ]).pick(:contractor_phone)
  end

  def display_address
    address.presence || contracts.where.not(contractor_address: [ nil, "" ]).pick(:contractor_address)
  end
end
