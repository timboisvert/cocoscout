class ProductionExpenseAllocation < ApplicationRecord
  belongs_to :production_expense
  belongs_to :show

  validates :allocated_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :show_id, uniqueness: { scope: :production_expense_id }

  scope :ordered, -> { joins(:show).order("shows.date_and_time ASC") }

  # Override this allocation with a custom amount
  def override!(amount, reason: nil)
    update!(
      allocated_amount: amount,
      is_override: true,
      override_reason: reason
    )
  end

  # Clear the override and recalculate
  def clear_override!
    update!(
      allocated_amount: production_expense.per_show_amount,
      is_override: false,
      override_reason: nil
    )
  end
end
