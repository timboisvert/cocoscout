class ProductionExpense < ApplicationRecord
  belongs_to :production
  has_many :allocations, class_name: "ProductionExpenseAllocation", dependent: :destroy

  validates :name, presence: true
  validates :total_amount, presence: true, numericality: { greater_than: 0 }
  validates :spread_method, presence: true, inclusion: {
    in: %w[fixed_months fixed_events date_range until_date specific_events]
  }

  # Validate spread parameters based on method
  validate :validate_spread_parameters

  SPREAD_METHODS = {
    "fixed_months" => "Spread over N months",
    "fixed_events" => "Spread over next N events",
    "date_range" => "Spread across shows in date range",
    "until_date" => "Spread from now until date",
    "specific_events" => "Select specific shows"
  }.freeze

  CATEGORIES = %w[venue production marketing equipment costumes props licensing insurance other].freeze

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(created_at: :desc) }

  # Event types that don't generate revenue (rehearsals, workshops, etc.)
  NON_REVENUE_EVENT_TYPES = %w[rehearsal workshop meeting other].freeze

  # Get shows that this expense applies to
  def applicable_shows
    scope = production.shows.where("date_and_time >= ?", effective_start_date)
    scope = scope.where("date_and_time <= ?", spread_end_date.end_of_day) if spread_end_date.present?
    scope = scope.where(canceled: false) if exclude_canceled?
    scope = scope.where(event_type: event_type_filter) if event_type_filter.is_a?(Array) && event_type_filter.any?
    scope = scope.where.not(event_type: NON_REVENUE_EVENT_TYPES) if exclude_non_revenue?

    case spread_method
    when "specific_events"
      scope = scope.where(id: selected_show_ids) if selected_show_ids.is_a?(Array) && selected_show_ids.any?
    when "fixed_events"
      scope = scope.order(:date_and_time).limit(spread_event_count.to_i)
    when "fixed_months"
      end_date = effective_start_date + spread_months.to_i.months
      scope = scope.where("date_and_time <= ?", end_date.end_of_day)
    end

    scope.order(:date_and_time)
  end

  # Calculate the per-show amount
  def per_show_amount
    shows = applicable_shows
    return 0 if shows.empty?
    (total_amount / shows.count).round(2)
  end

  # Recalculate all allocations (preserves overrides)
  def recalculate_allocations!
    # Remove non-override allocations
    allocations.where(is_override: false).destroy_all

    per_amount = per_show_amount

    applicable_shows.each do |show|
      # Skip if there's already an override for this show
      next if allocations.exists?(show: show, is_override: true)

      allocations.create!(
        show: show,
        allocated_amount: per_amount,
        is_override: false
      )
    end
  end

  # Get allocation for a specific show
  def allocation_for(show)
    allocations.find_by(show: show)
  end

  # Total amount allocated (may differ from total_amount if overrides exist)
  def total_allocated
    allocations.sum(:allocated_amount)
  end

  # Remaining unallocated amount
  def unallocated_amount
    total_amount - total_allocated
  end

  # Human-readable spread description
  def spread_description
    case spread_method
    when "fixed_months"
      "#{spread_months} months from #{effective_start_date.strftime('%b %Y')}"
    when "fixed_events"
      "Next #{spread_event_count} events"
    when "date_range"
      "#{spread_start_date&.strftime('%b %d, %Y')} to #{spread_end_date&.strftime('%b %d, %Y')}"
    when "until_date"
      "Until #{spread_end_date&.strftime('%b %d, %Y')}"
    when "specific_events"
      "#{selected_show_ids&.count || 0} selected shows"
    else
      "Unknown"
    end
  end

  private

  def effective_start_date
    spread_start_date.presence || purchase_date.presence || created_at&.to_date || Date.current
  end

  def validate_spread_parameters
    case spread_method
    when "fixed_months"
      if spread_months.blank? || spread_months < 1
        errors.add(:spread_months, "must be at least 1")
      end
    when "fixed_events"
      if spread_event_count.blank? || spread_event_count < 1
        errors.add(:spread_event_count, "must be at least 1")
      end
    when "date_range"
      if spread_start_date.blank? || spread_end_date.blank?
        errors.add(:base, "Both start and end dates are required for date range spread")
      elsif spread_end_date < spread_start_date
        errors.add(:spread_end_date, "must be after start date")
      end
    when "until_date"
      if spread_end_date.blank?
        errors.add(:spread_end_date, "is required")
      end
    when "specific_events"
      if selected_show_ids.blank? || !selected_show_ids.is_a?(Array) || selected_show_ids.empty?
        errors.add(:selected_show_ids, "must select at least one show")
      end
    end
  end
end
