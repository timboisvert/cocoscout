class TicketFeeTemplate < ApplicationRecord
  belongs_to :organization

  validates :name, presence: true, uniqueness: { scope: :organization_id }
  validates :flat_per_ticket, numericality: { greater_than_or_equal_to: 0 }
  validates :percentage, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  scope :ordered, -> { order(:name) }
  scope :default_first, -> { order(is_default: :desc, name: :asc) }

  # Calculate the fee amount for a given ticket count and revenue
  def calculate_fee(ticket_count:, ticket_revenue:)
    flat_total = (flat_per_ticket || 0) * ticket_count.to_i
    percentage_total = (percentage || 0) / 100.0 * ticket_revenue.to_f
    (flat_total + percentage_total).round(2)
  end

  # Description of the fee structure for display
  def fee_description
    parts = []
    parts << "$#{'%.2f' % flat_per_ticket}/ticket" if flat_per_ticket.to_f > 0
    parts << "#{'%.2f' % percentage}%" if percentage.to_f > 0
    parts.empty? ? "No fee" : parts.join(" + ")
  end

  # JSON representation for storing in ShowFinancials.ticket_fees
  def to_fee_hash(ticket_count:, ticket_revenue:)
    {
      "template_id" => id,
      "name" => name,
      "flat" => flat_per_ticket.to_f,
      "pct" => percentage.to_f,
      "amount" => calculate_fee(ticket_count: ticket_count, ticket_revenue: ticket_revenue)
    }
  end
end
