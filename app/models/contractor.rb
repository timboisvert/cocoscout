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

  # Payment methods (compatible with ShowPayoutLineItem's polymorphic payee interface)
  def venmo_configured?
    venmo_identifier.present?
  end

  def venmo_ready_for_payouts?
    venmo_configured?
  end

  def zelle_configured?
    zelle_identifier.present?
  end

  def zelle_ready_for_payouts?
    zelle_configured?
  end

  def any_payment_method_configured?
    venmo_configured? || zelle_configured?
  end

  def formatted_venmo_identifier
    return nil unless venmo_identifier.present?
    "@#{venmo_identifier.delete('@')}"
  end

  def formatted_zelle_identifier
    zelle_identifier
  end

  def venmo_payment_link(amount, note = nil)
    return nil unless venmo_configured?

    username = venmo_identifier.delete("@")
    params = {
      txn: "pay",
      recipients: username,
      amount: amount.to_f,
      note: note
    }.compact

    "venmo://paycharge?#{params.to_query}"
  end

  def preferred_payment_info
    if venmo_configured?
      { method: "venmo", identifier: formatted_venmo_identifier }
    elsif zelle_configured?
      { method: "zelle", identifier: formatted_zelle_identifier }
    end
  end

  def initials
    name.to_s.split(/\s+/).map { |w| w[0] }.join.upcase.first(2)
  end
end
