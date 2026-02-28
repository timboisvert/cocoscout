# frozen_string_literal: true

class Contract < ApplicationRecord
  belongs_to :organization

  has_many :contract_documents, dependent: :destroy
  has_many :contract_payments, dependent: :destroy
  has_many :space_rentals, dependent: :destroy
  has_many :productions, dependent: :nullify

  # Status enum
  enum :status, {
    draft: "draft",
    active: "active",
    completed: "completed",
    cancelled: "cancelled"
  }, default: :draft, prefix: :status

  validates :contractor_name, presence: true

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :upcoming, -> { status_active.where("contract_end_date >= ?", Date.current).order(:contract_start_date) }
  scope :past, -> { where("contract_end_date < ?", Date.current).order(contract_end_date: :desc) }

  # Allow overlap flag - when true, skip overlap validation on space rentals
  attr_accessor :allow_overlap

  # Lifecycle methods
  def activate!
    return false unless status_draft?
    return false unless valid_for_activation?

    transaction do
      create_records_from_draft!
      update!(
        status: :active,
        activated_at: Time.current
        # Keep draft_data - it contains the full contract config (services, payment_config, etc.)
      )
    end

    true
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.message)
    false
  end

  def complete!
    return false unless status_active?

    update!(
      status: :completed,
      completed_at: Time.current
    )
  end

  def cancel!(delete_events: false)
    return false if status_cancelled?

    transaction do
      if delete_events
        # Delete associated productions and their shows
        productions.destroy_all
      else
        # Mark associated shows as cancelled
        productions.each do |production|
          production.shows.update_all(canceled: true)
        end
      end

      update!(
        status: :cancelled,
        cancelled_at: Time.current
      )
    end

    true
  end

  # Draft data helpers
  def draft_bookings
    draft_data["bookings"] || []
  end

  def draft_booking_rules
    draft_data["booking_rules"] || {}
  end

  def draft_payments
    draft_data["payments"] || []
  end

  def draft_payment_structure
    draft_data["payment_structure"] || "flat_fee"
  end

  def draft_payment_config
    draft_data["payment_config"] || {}
  end

  def draft_services
    draft_data["services"] || []
  end

  def update_draft_step(step_name, data)
    self.draft_data = draft_data.merge(step_name.to_s => data)
    save!
  end

  # Amend data helpers (for amending existing active contracts)
  def amend_data
    draft_data["amend"] || {}
  end

  def update_amend_data(data)
    self.draft_data = draft_data.merge("amend" => data)
    save!
  end

  def clear_amend_data
    new_data = draft_data.except("amend")
    self.draft_data = new_data
    save!
  end

  # Validation for activation
  def valid_for_activation?
    errors.clear

    errors.add(:base, "Must have at least one booking") if draft_bookings.empty? && space_rentals.empty?
    errors.add(:base, "Contract start date is required") if contract_start_date.blank?
    errors.add(:base, "Contract end date is required") if contract_end_date.blank?

    errors.empty?
  end

  # Financial summary
  def total_incoming
    contract_payments.where(direction: "incoming").sum(:amount)
  end

  def total_outgoing
    contract_payments.where(direction: "outgoing").sum(:amount)
  end

  def net_amount
    total_incoming - total_outgoing
  end

  def pending_payments
    contract_payments.where(status: "pending")
  end

  def overdue_payments
    contract_payments.where(status: "pending").where("due_date < ?", Date.current)
  end

  # Display helpers
  def display_name
    production_name.presence || contractor_name
  end

  def date_range
    return nil if contract_start_date.blank? || contract_end_date.blank?

    if contract_start_date == contract_end_date
      contract_start_date.strftime("%B %d, %Y")
    else
      "#{contract_start_date.strftime('%B %d')} - #{contract_end_date.strftime('%B %d, %Y')}"
    end
  end

  private

  def create_records_from_draft!
    # Create space rentals from draft bookings
    draft_bookings.each do |booking|
      starts_at = Time.zone.parse(booking["starts_at"])

      # Handle both data formats: ends_at directly, or duration-based calculation
      ends_at = if booking["ends_at"].present?
        Time.zone.parse(booking["ends_at"])
      else
        duration_hours = booking["duration"].to_f
        starts_at + duration_hours.hours
      end

      # Get location_id (required) and space_id (optional for "Entire venue")
      location_id = booking["location_id"]
      space_id = booking["location_space_id"] || booking["space_id"]
      space_id = nil if space_id.blank? # Convert empty string to nil

      # Handle event_starts_at if different from rental start
      event_starts_at = booking["event_starts_at"].present? ? Time.zone.parse(booking["event_starts_at"]) : nil
      event_ends_at = booking["event_ends_at"].present? ? Time.zone.parse(booking["event_ends_at"]) : nil

      space_rentals.create!({
        location_id: location_id,
        location_space_id: space_id,
        starts_at: starts_at,
        ends_at: ends_at,
        event_starts_at: event_starts_at,
        event_ends_at: event_ends_at,
        notes: booking["notes"],
        confirmed: true,
        allow_overlap: allow_overlap
      })
    end

    # Create payments from draft payments
    draft_payments.each do |payment|
      contract_payments.create!(
        description: payment["description"],
        amount: payment["amount"],
        amount_tbd: payment["amount_tbd"] || false,
        direction: payment["direction"],
        due_date: payment["due_date"],
        notes: payment["notes"]
      )
    end

    # Always create a production for the contract
    # This makes the events visible in Shows & Events
    prod_data = draft_data["production"] || {}
    production = productions.create!(
      organization: organization,
      name: production_name.presence || prod_data["name"].presence || contractor_name,
      production_type: "third_party",
      contact_email: contractor_email
    )

    # Create shows for each space rental (booking)
    space_rentals.reload.each do |rental|
      duration_minutes = ((rental.ends_at - rental.starts_at) / 60).to_i
      production.shows.create!(
        date_and_time: rental.starts_at,
        duration_minutes: duration_minutes,
        location: rental.location,
        location_space: rental.location_space,
        space_rental: rental,
        event_type: prod_data["event_type"].presence || "show"
      )
    end
  end
end
