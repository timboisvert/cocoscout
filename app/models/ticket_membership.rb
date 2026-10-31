# frozen_string_literal: true

# One person's membership (advanced ticketing §2b): their level, when it
# runs, and its money (like a credit pass holding). Its page is
# /tickets/my-membership/<token>; the holder's email is their identity
# (an emailed code, Ticketing::BuyerVerification).
class TicketMembership < ApplicationRecord
  STATUSES = %w[pending active expired canceled renewed].freeze
  STATUS_LABELS = { "pending" => "Not paid", "active" => "Active", "expired" => "Expired", "canceled" => "Canceled", "renewed" => "Renewed" }.freeze
  RENEW_BEFORE = 45.days
  RENEW_AFTER = 90.days

  belongs_to :organization
  belongs_to :level, class_name: "TicketMembershipLevel", foreign_key: :ticket_membership_level_id, inverse_of: :memberships
  belongs_to :ticket_purchase, optional: true
  belongs_to :follower, optional: true
  belongs_to :renewed_from, class_name: "TicketMembership", optional: true
  has_many :ticket_orders, dependent: :nullify

  validates :status, inclusion: { in: STATUSES }
  validates :holder_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  before_validation { self.token ||= SecureRandom.urlsafe_base64(24) }

  scope :active, -> { where(status: "active") }
  scope :live, ->(on = Date.current) { active.where("ends_on >= ?", on) }

  def to_param = token
  def status_label = STATUS_LABELS.fetch(status)
  def first_name = holder_name.to_s.split.first.presence || "there"

  def usable?(on = Date.current)
    status == "active" && on.between?(starts_on, ends_on)
  end

  # Renewal opens 45 days before the end and stays open 90 days after.
  def renewable?(on = Date.current)
    return false unless status.in?(%w[active expired]) && level.status == "on_sale"

    on >= ends_on - RENEW_BEFORE && on <= ends_on + RENEW_AFTER
  end

  def days_left(on = Date.current) = (ends_on - on).to_i

  # Perks, asked by the checkout, the seat picker and the exchange flow.
  def discount_percent = usable? ? level.discount_percent : 0
  def presale? = usable? && level.presale_days.positive?
  def better_seats? = usable? && level.better_seats
  def section_upgrade? = usable? && level.section_upgrade
  def free_exchanges? = usable? && level.free_exchanges
end
