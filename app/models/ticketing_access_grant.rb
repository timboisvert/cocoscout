# frozen_string_literal: true

# Door access for someone who isn't an org manager — a staff member or any
# CocoScout user the theater adds in Ticketing settings. "Check in" scans and
# admits; "Box office" also sells at the door, gives comps, and looks up or
# resends orders. Refunds, prices and settings stay with managers. Revoking
# keeps the row, so who had access when is never lost.
class TicketingAccessGrant < ApplicationRecord
  LEVELS = %w[check_in box_office].freeze
  LEVEL_LABELS = { "check_in" => "Check in", "box_office" => "Box office" }.freeze

  belongs_to :organization
  belongs_to :user
  belongs_to :granted_by, class_name: "User", optional: true
  belongs_to :revoked_by, class_name: "User", optional: true

  validates :access_level, inclusion: { in: LEVELS }
  validates :user_id, uniqueness: { scope: :organization_id, conditions: -> { where(revoked_at: nil) } }, unless: :revoked?

  scope :active, -> { where(revoked_at: nil) }

  def revoked?
    revoked_at.present?
  end

  def box_office?
    access_level == "box_office"
  end

  def revoke!(by: nil)
    update!(revoked_at: Time.current, revoked_by: by)
  end
end
