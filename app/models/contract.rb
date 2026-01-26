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

  # Lifecycle methods
  def activate!
    return false unless status_draft?
    return false unless valid_for_activation?

    transaction do
      create_records_from_draft!
      update!(
        status: :active,
        activated_at: Time.current,
        draft_data: {} # Clear draft data after activation
      )
    end

    true
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

  def draft_payments
    draft_data["payments"] || []
  end

  def draft_services
    draft_data["services"] || []
  end

  def update_draft_step(step_name, data)
    self.draft_data = draft_data.merge(step_name.to_s => data)
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
      space_rentals.create!(
        location_space_id: booking["location_space_id"],
        starts_at: booking["starts_at"],
        ends_at: booking["ends_at"],
        notes: booking["notes"],
        confirmed: true
      )
    end

    # Create payments from draft payments
    draft_payments.each do |payment|
      contract_payments.create!(
        description: payment["description"],
        amount: payment["amount"],
        direction: payment["direction"],
        due_date: payment["due_date"],
        notes: payment["notes"]
      )
    end

    # Create production if specified in draft
    if draft_data["production"].present?
      prod_data = draft_data["production"]
      production = productions.create!(
        organization: organization,
        name: prod_data["name"] || contractor_name,
        production_type: "third_party",
        contact_email: contractor_email
      )

      # Create shows for each booking
      space_rentals.each do |rental|
        production.shows.create!(
          date_and_time: rental.starts_at,
          location: rental.location_space.location,
          location_space: rental.location_space,
          space_rental: rental,
          event_type: prod_data["event_type"] || "performance"
        )
      end
    end
  end
end
