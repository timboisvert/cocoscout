class ExpenseItem < ApplicationRecord
  belongs_to :show_financials

  has_one_attached :receipt

  validates :category, presence: true
  validates :amount, presence: true, numericality: { greater_than: 0 }

  validate :acceptable_receipt

  # The one list (config/money_categories.yml); older rows keep their old
  # keys and MoneyCategories reads them as what they meant.
  CATEGORIES = MoneyCategories.spending_keys

  scope :ordered, -> { order(:position) }

  after_commit { show_financials&.reload&.post_to_books }

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
