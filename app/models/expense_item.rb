class ExpenseItem < ApplicationRecord
  belongs_to :show_financials

  has_one_attached :receipt

  validates :category, presence: true
  validates :amount, presence: true, numericality: { greater_than: 0 }

  validate :acceptable_receipt

  # Categories matching existing expense_details structure
  CATEGORIES = %w[venue production marketing talent other].freeze

  scope :ordered, -> { order(:position) }

  private

  def acceptable_receipt
    return unless receipt.attached?

    unless receipt.content_type.in?(%w[application/pdf image/jpeg image/png])
      errors.add(:receipt, "must be PDF, JPG, or PNG")
    end

    # Limit file size to 10MB
    if receipt.byte_size > 10.megabytes
      errors.add(:receipt, "must be less than 10MB")
    end
  end
end
