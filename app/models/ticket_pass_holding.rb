# frozen_string_literal: true

# One credit pass someone bought (a punch card or a season pass): its credits,
# what each counts (the pass price ÷ credits), and when it ends. Its page
# (/tickets/passes/holding/<token>) is where the holder uses credits; the door
# can use one too. Its money stays held until the pass ends, then what's left
# unused is the organization's (TicketPassCredits).
class TicketPassHolding < ApplicationRecord
  STATUSES = %w[pending active ended canceled].freeze

  belongs_to :organization
  belongs_to :ticket_pass
  belongs_to :ticket_purchase, optional: true
  has_many :tickets, dependent: :restrict_with_error
  has_many :tax_lines, as: :taxable, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :credits, numericality: { only_integer: true, greater_than: 0 }

  before_validation { self.token ||= SecureRandom.urlsafe_base64(24) }

  scope :active, -> { where(status: "active") }

  def to_param
    token
  end

  # Credits spent: tickets it made that still stand.
  def credits_used
    tickets.where(status: Ticket::SOLD_STATUSES).count
  end

  def credits_left
    [ credits - credits_used, 0 ].max
  end

  def usable?(on = Date.current)
    status == "active" && on <= ends_on && credits_left.positive?
  end

  def season?
    ticket_pass.kind == "season"
  end
end
