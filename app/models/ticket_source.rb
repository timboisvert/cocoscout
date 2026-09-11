# frozen_string_literal: true

# One place an organization sells tickets — Eventbrite, HotTix, the box office,
# at the door. Named by the org in Money settings, and picked per line when a
# show's ticket sales are entered.
#
# Archived, never deleted: a sales line that went through a source the org has
# stopped using still has to say where that money came from.
class TicketSource < ApplicationRecord
  belongs_to :organization

  has_many :ticket_sales_lines, dependent: :nullify

  normalizes :name, with: ->(n) { n.squish }

  validates :name, presence: true, length: { maximum: 100 }
  validates :name, uniqueness: { scope: :organization_id, case_sensitive: false }

  scope :ordered, -> { order(:position, :name) }
  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  def archived?
    archived_at.present?
  end

  def archive!
    update!(archived_at: Time.current)
  end

  def restore!
    update!(archived_at: nil)
  end
end
