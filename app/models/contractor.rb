# frozen_string_literal: true

class Contractor < ApplicationRecord
  include StripeConnectable

  belongs_to :organization
  # A Contractor wraps a Person — the identity that logs in and is the payout
  # payee (Stripe/bank + ledger live on the Person). The Contractor is a
  # container for that party's contracts.
  belongs_to :person, optional: true
  has_many :contracts, dependent: :nullify
  has_many :payout_ledger_entries, as: :payee, dependent: :destroy

  validates :name, presence: true
  validates :name, uniqueness: { scope: :organization_id, case_sensitive: false }

  # Find or create the backing Person (in this org, matched by email). Returns
  # nil when there's no email to build one from. Idempotent; safe for backfill.
  def ensure_person!
    return person if person_id.present?
    return nil if email.blank?

    linked = organization.people.where("LOWER(email) = ?", email.to_s.downcase).first ||
             organization.people.create!(name: name.to_s.strip, email: email)
    update!(person: linked)
    linked
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("Contractor##{id} ensure_person! failed: #{e.message}")
    nil
  end

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

  def initials
    name.to_s.split(/\s+/).map { |w| w[0] }.join.upcase.first(2)
  end
end
