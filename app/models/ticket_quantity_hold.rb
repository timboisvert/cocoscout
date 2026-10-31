# frozen_string_literal: true

# A block of general-admission seats kept out of sale for someone (a group
# booking, later a members' block): so many of one ticket type, or of the
# date as a whole when the type is blank. Ticketing::Inventory counts a live
# hold as taken, so the public picker and the door never sell into it.
# Released, it's history: the seats are back on sale.
class TicketQuantityHold < ApplicationRecord
  belongs_to :organization
  belongs_to :ticket_listing
  belongs_to :ticket_tier, optional: true
  belongs_to :owner, polymorphic: true

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }

  scope :live, -> { where(released_at: nil) }

  def live? = released_at.nil?

  def release!
    update!(released_at: Time.current) if live?
  end
end
