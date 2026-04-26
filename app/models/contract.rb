# frozen_string_literal: true

class Contract < ApplicationRecord
  belongs_to :organization
  belongs_to :contractor, optional: true

  has_many :contract_documents, dependent: :destroy
  has_many :contract_payments, dependent: :destroy
  has_many :space_rentals, dependent: :destroy
  has_many :productions, dependent: :nullify
  has_many :course_offerings, dependent: :nullify

  # Status enum
  enum :status, {
    draft: "draft",
    active: "active",
    completed: "completed",
    cancelled: "cancelled"
  }, default: :draft, prefix: :status

  validates :contractor_name, presence: true

  # Callbacks to sync contractor data
  before_save :sync_contractor_info

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
        activated_at: Time.current,
        skip_event_creation: false
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

    transaction do
      update!(
        status: :completed,
        completed_at: Time.current
      )

      # Archive associated productions
      productions.where(archived_at: nil).update_all(archived_at: Time.current)
    end

    true
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

  # Revenue share financial helpers — calculates from show-level financials
  def contractor_share_percentage
    return nil unless revenue_share?
    100.0 - revenue_share_percentage
  end

  # Returns { confirmed_revenue: X, tbd_count: N, contractor_share: Y }
  def revenue_share_summary
    return nil unless revenue_share?

    all_shows = productions.flat_map { |p| p.shows.includes(:show_financials).to_a }
    confirmed_shows = all_shows.select { |s| s.show_financials&.has_data? }
    pending_shows = all_shows - confirmed_shows

    confirmed_revenue = confirmed_shows.sum { |s| s.show_financials.total_revenue }
    our_share_amount = (confirmed_revenue * revenue_share_percentage / 100.0).round(2)
    contractor_share_amount = (confirmed_revenue * contractor_share_percentage / 100.0).round(2)

    {
      confirmed_revenue: confirmed_revenue,
      confirmed_count: confirmed_shows.count,
      pending_count: pending_shows.count,
      our_share: our_share_amount,
      contractor_share: contractor_share_amount,
      total_shows: all_shows.count
    }
  end

  # Returns financial summary for ticket_revenue_minus_fee contracts
  def flat_fee_revenue_summary
    return nil unless ticket_revenue_minus_fee?

    all_shows = productions.flat_map { |p| p.shows.includes(:show_financials).to_a }
    confirmed_shows = all_shows.select { |s| s.show_financials&.has_data? }
    pending_shows = all_shows - confirmed_shows

    confirmed_revenue = confirmed_shows.sum { |s| s.show_financials.total_revenue }
    fee = flat_fee_amount
    contractor_amount = [ confirmed_revenue - fee, 0 ].max

    {
      confirmed_revenue: confirmed_revenue,
      confirmed_count: confirmed_shows.count,
      pending_count: pending_shows.count,
      our_share: fee,
      contractor_share: contractor_amount,
      total_shows: all_shows.count
    }
  end

  # Find the matching ContractPayment for a given show based on settlement frequency
  def find_payment_for_show(show)
    return nil unless revenue_share?

    # First, try direct show_id link
    direct = contract_payments.find_by(show_id: show.id)
    return direct if direct

    settlement = draft_payment_config["revenue_settlement"] || "monthly"
    # Direction-agnostic: contracts can be incoming (contractor pays us) or outgoing (we pay contractor)
    revenue_payments = contract_payments.where(amount_tbd: true)
                                        .or(contract_payments.where("description LIKE ?", "%Revenue Share%"))
                                        .order(:due_date)

    payment = case settlement
    when "per_event", "next_day", "same_day"
      # Match by positional order: sort shows and payments by date, pair 1:1
      all_shows = productions.flat_map { |p| p.shows.order(:date_and_time).to_a }
      show_index = all_shows.index { |s| s.id == show.id }
      show_index ? revenue_payments.to_a[show_index] : nil
    when "weekly"
      show_week_start = show.date_and_time.to_date.beginning_of_week
      revenue_payments.find { |p| p.due_date.beginning_of_week == show_week_start }
    else # monthly
      show_month = show.date_and_time.to_date.beginning_of_month
      revenue_payments.find { |p| p.due_date.beginning_of_month == show_month }
    end

    # Link the show_id for future lookups if we found a match
    if payment && payment.show_id.nil?
      payment.update_column(:show_id, show.id)
    end

    payment
  end

  # Get all shows that map to a given ContractPayment
  def shows_for_payment(payment)
    # If payment has a direct show link, use it
    if payment.show_id.present?
      show = Show.includes(:show_financials).find_by(id: payment.show_id)
      return show ? [ show ] : []
    end

    settlement = draft_payment_config["revenue_settlement"] || "monthly"
    all_shows = productions.flat_map { |p| p.shows.includes(:show_financials).order(:date_and_time).to_a }

    case settlement
    when "per_event", "next_day", "same_day"
      # Match by positional order: sort payments by due_date, pair 1:1 with shows by date
      revenue_payments = contract_payments.where("amount_tbd = ? OR description LIKE ?", true, "%Revenue Share%")
                                          .order(:due_date).to_a
      payment_index = revenue_payments.index { |p| p.id == payment.id }
      show = payment_index ? all_shows[payment_index] : nil
      if show
        # Link for future lookups
        payment.update_column(:show_id, show.id) if payment.show_id.nil?
        [ show ]
      else
        []
      end
    when "weekly"
      week_start = payment.due_date.beginning_of_week
      all_shows.select { |s| s.date_and_time.to_date.beginning_of_week == week_start }
    else # monthly
      month_start = payment.due_date.beginning_of_month
      all_shows.select { |s| s.date_and_time.to_date.beginning_of_month == month_start }
    end
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

  # Revenue projection helpers
  def revenue_share?
    draft_payment_structure == "revenue_share"
  end

  def ticket_revenue_minus_fee?
    draft_payment_structure == "flat_fee" && draft_payment_config["flat_fee_direction"] == "ticket_revenue_minus_fee"
  end

  def flat_fee_amount
    draft_payment_config["flat_fee_amount"].to_f
  end

  def revenue_share_percentage
    return nil unless revenue_share?
    draft_payment_config["revenue_our_share"].to_f
  end

  def has_revenue_projection?
    revenue_projections.present? && revenue_projections["scenarios"].present?
  end

  def revenue_projection_scenario(name = "default")
    return nil unless has_revenue_projection?
    revenue_projections["scenarios"]&.find { |s| s["name"] == name }
  end

  def set_revenue_projection(ticket_price_low:, ticket_price_high:, tickets_sold_low:, tickets_sold_high:, notes: nil, scenario_name: "default")
    scenarios = (revenue_projections["scenarios"] || []).reject { |s| s["name"] == scenario_name }
    scenarios << {
      "name" => scenario_name,
      "ticket_price_low" => ticket_price_low.to_f,
      "ticket_price_high" => ticket_price_high.to_f,
      "tickets_sold_low" => tickets_sold_low.to_i,
      "tickets_sold_high" => tickets_sold_high.to_i,
      "notes" => notes,
      "updated_at" => Time.current.iso8601
    }
    update!(revenue_projections: revenue_projections.merge("scenarios" => scenarios))
  end

  def projected_gross_revenue_range(scenario_name = "default")
    scenario = revenue_projection_scenario(scenario_name)
    return nil unless scenario

    low = scenario["ticket_price_low"].to_f * scenario["tickets_sold_low"].to_i
    high = scenario["ticket_price_high"].to_f * scenario["tickets_sold_high"].to_i
    { low: low, high: high }
  end

  def projected_our_revenue_range(scenario_name = "default")
    gross = projected_gross_revenue_range(scenario_name)
    return nil unless gross && revenue_share_percentage

    share = revenue_share_percentage / 100.0
    { low: (gross[:low] * share).round(2), high: (gross[:high] * share).round(2) }
  end

  def total_received_payments
    contract_payments.where(direction: "incoming", status: "paid").sum(:amount)
  end

  def total_pending_payments
    contract_payments.where(direction: "incoming", status: "pending").sum(:amount)
  end

  # Sync paid course offering payouts to contract payments
  def sync_course_payouts_to_payments
    return if course_offerings.empty?

    # Find all paid line items from course offering payouts
    paid_items = CourseOfferingPayoutLineItem
      .joins(course_offering_payout: :course_offering)
      .where(course_offering_payout: { course_offering_id: course_offerings.ids })
      .where(payee_type: "Contractor", payee_id: contractor_id)
      .where(manually_paid: true)

    paid_items.each do |item|
      # Find matching pending ContractPayment (outgoing, for this contractor)
      payments_to_sync = contract_payments
        .where(direction: "outgoing", status: "pending")
        .select { |p| p.description&.downcase&.include?("revenue share") }

      payments_to_sync.each do |payment|
        payment.mark_paid!(
          paid_on: item.paid_at.to_date,
          method: item.payment_method,
          reference: "Course offering payout",
          amount: item.amount_cents / 100.0
        )
      end
    end
  end

  private

  def sync_contractor_info
    return unless contractor_id.present?

    # If contractor is set, ensure contractor_name comes from the contractor
    self.contractor_name = contractor.name if contractor_name.blank? || contractor_id_changed?

    # Optionally sync contact info from contractor if not set on contract
    if contractor_email.blank? && contractor.email.present?
      self.contractor_email = contractor.email
    end
    if contractor_phone.blank? && contractor.phone.present?
      self.contractor_phone = contractor.phone
    end
    if contractor_address.blank? && contractor.address.present?
      self.contractor_address = contractor.address
    end
  end

  def create_records_from_draft!
    rentals = []

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

      rental = space_rentals.create!({
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

      event_type = booking["event_type"] || "show"
      rentals << { rental: rental, event_type: event_type }
    end

    # Create payments from draft payments
    created_payments = []
    draft_payments.each do |payment|
      created_payments << contract_payments.create!(
        description: payment["description"],
        amount: payment["amount"],
        amount_tbd: payment["amount_tbd"] || false,
        direction: payment["direction"],
        due_date: payment["due_date"],
        notes: payment["notes"]
      )
    end

    # Always create a production and shows for all bookings
    created_shows = []
    if rentals.any?
      prod_data = draft_data["production"] || {}
      # Use existing production if one is already linked (e.g., from course offering wizard)
      production = productions.first || productions.create!(
        organization: organization,
        name: production_name.presence || prod_data["name"].presence || contractor_name,
        production_type: "third_party",
        contact_email: contractor_email
      )

      rentals.each do |info|
        rental = info[:rental]
        duration_minutes = ((rental.ends_at - rental.starts_at) / 60).to_i
        show = production.shows.create!(
          date_and_time: rental.starts_at,
          duration_minutes: duration_minutes,
          location: rental.location,
          location_space: rental.location_space,
          space_rental: rental,
          event_type: info[:event_type]
        )
        created_shows << show
      end
    end

    # Link per-event payments to their corresponding shows
    link_payments_to_shows(created_payments, created_shows)
  end

  # Link per-event contract payments to their corresponding shows by matching dates
  def link_payments_to_shows(payments, shows)
    return if payments.empty? || shows.empty?

    settlement = draft_payment_config["revenue_settlement"] || "monthly"
    structure = draft_payment_structure

    # Only link for per-event or per-event revenue share settlements
    per_event_structures = %w[per_event]
    per_event_settlements = %w[per_event same_day next_day]

    should_link = per_event_structures.include?(structure) ||
                  (structure == "revenue_share" && per_event_settlements.include?(settlement))
    return unless should_link

    # Sort both by date and pair 1:1
    sorted_shows = shows.sort_by(&:date_and_time)
    sorted_payments = payments.select { |p| p.amount_tbd? || p.description&.include?("Event") || p.description&.include?("Revenue Share") }
                              .sort_by(&:due_date)

    sorted_payments.each_with_index do |payment, i|
      next unless sorted_shows[i]
      payment.update_column(:show_id, sorted_shows[i].id)
    end
  end
end
