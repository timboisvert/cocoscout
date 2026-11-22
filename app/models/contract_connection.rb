# frozen_string_literal: true

# A contract connected to the contractor's own organization on CocoScout
# (Tim, 2026-11-14 to 17; plan: one show, two organizations). The contractor
# requests it for one of their organizations and a production there; the
# organization that wrote the contract accepts or declines. While connected,
# the contract's dates appear in that production (Show#linked_show), and the
# contractor's organization sees their ticket sales, read-only.
#
#   requested  waiting for the organization that wrote the contract
#   connected  accepted: the dates and the numbers flow
#   declined   they said no, with a note
#   withdrawn  the contractor took the request back
#   unlinked   either side ended it; the dates already there stay, as the
#              contractor's own
class ContractConnection < ApplicationRecord
  STATUSES = %w[requested connected declined withdrawn unlinked].freeze
  LIVE = %w[requested connected].freeze
  LATER_CONTRACTS = %w[ask production all].freeze
  # How long a request waits before the organization is reminded, once.
  REMIND_AFTER = 3.days
  # The box office's own choices (TicketingProfile), one layer down.
  TEAM_MANAGER_SALES = %w[everything numbers nothing].freeze
  TEAM_VIEWER_SALES = %w[numbers nothing].freeze
  CAST_SALES = %w[production_cast show_cast nothing].freeze

  belongs_to :organization
  belongs_to :contract
  belongs_to :linked_organization, class_name: "Organization"
  belongs_to :linked_production, class_name: "Production", optional: true
  belongs_to :requested_by, class_name: "User"
  belongs_to :answered_by, class_name: "User", optional: true
  belongs_to :ended_by, class_name: "User", optional: true
  belongs_to :pay_choice_by, class_name: "User", optional: true
  # Who on the contractor's side is notified as its tickets sell (LinkedSaleNotices).
  has_many :watchers, class_name: "ContractConnectionWatcher", dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :later_contracts, inclusion: { in: LATER_CONTRACTS }
  validates :team_manager_sales, inclusion: { in: TEAM_MANAGER_SALES }
  validates :team_viewer_sales, inclusion: { in: TEAM_VIEWER_SALES }
  validates :cast_sales, inclusion: { in: CAST_SALES }
  validates :note, :answer_note, length: { maximum: 2000 }
  validate :organizations_differ
  validate :production_is_theirs
  validate :has_somewhere_to_put_the_dates, on: :create

  scope :live, -> { where(status: LIVE) }
  scope :connected, -> { where(status: "connected") }
  scope :requested, -> { where(status: "requested") }

  def requested? = status == "requested"
  def connected? = status == "connected"
  def live? = status.in?(LIVE)

  # The production's name on their side, before and after it exists.
  def production_name = linked_production&.name || new_production_name.presence || contract.production&.name || contract.production_name

  # What the linked organization's production team and cast see of the
  # ticket sales (TicketSalesAccess levels), as TicketingProfile reads its own.
  def team_level(role)
    case role
    when "manager" then { "everything" => :full, "numbers" => :numbers }[team_manager_sales]
    when "viewer" then (:numbers if team_viewer_sales == "numbers")
    end
  end

  def cast_level = (:numbers unless cast_sales == "nothing")

  # What the organization chose for later contracts, said to the
  # contractor's side (ContractConnections.standing_yes acts on it).
  def later_contracts_words
    seller = organization.name
    case later_contracts
    when "production"
      "#{seller} has agreed to connect later contracts for #{contract.production&.name || 'this production'}. You can connect each one from My Contracts without waiting for approval."
    when "all" then "#{seller} has agreed to connect every later contract with you. You can connect each one from My Contracts without waiting for approval."
    else "#{seller} will get a request for each later contract."
    end
  end

  private

  def organizations_differ
    errors.add(:base, "That's the organization the contract is with.") if linked_organization_id == organization_id
  end

  def production_is_theirs
    return unless linked_production && linked_production.organization_id != linked_organization_id

    errors.add(:base, "That production isn't in that organization.")
  end

  def has_somewhere_to_put_the_dates
    errors.add(:base, "Choose a production for the dates.") if linked_production.nil? && new_production_name.blank?
  end
end
