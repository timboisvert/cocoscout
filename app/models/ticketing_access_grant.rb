# frozen_string_literal: true

# Door access for someone who isn't an org manager — a staff member or any
# CocoScout user the theater adds in Ticketing settings. "Check in" scans and
# admits; "Box office" also sells at the door, gives comps, and looks up or
# resends orders. Refunds, prices and settings stay with managers. Revoking
# keeps the row, so who had access when is never lost.
#
# Someone not on CocoScout yet is invited by email: the grant waits with no
# user and an invitation token until they accept (DoorInvitationsController).
class TicketingAccessGrant < ApplicationRecord
  LEVELS = %w[check_in box_office].freeze
  LEVEL_LABELS = { "check_in" => "Check in", "box_office" => "Box office" }.freeze

  belongs_to :organization
  belongs_to :user, optional: true
  belongs_to :granted_by, class_name: "User", optional: true
  belongs_to :revoked_by, class_name: "User", optional: true

  normalizes :invited_email, with: ->(email) { email.to_s.strip.downcase.presence }

  validates :access_level, inclusion: { in: LEVELS }
  validates :user_id, uniqueness: { scope: :organization_id, conditions: -> { where(revoked_at: nil) } },
                      unless: -> { revoked? || user_id.nil? }
  validates :invited_email, format: { with: URI::MailTo::EMAIL_REGEXP }, if: -> { user_id.nil? }

  scope :active, -> { where(revoked_at: nil) }
  scope :pending_invites, -> { active.where(user_id: nil) }

  def self.invite!(organization:, email:, name:, level:, by:)
    grant = organization.ticketing_access_grants.pending_invites.find_or_initialize_by(invited_email: email.to_s.strip.downcase)
    grant.assign_attributes(invited_name: name.to_s.squish.presence, access_level: level, granted_by: by, invited_at: Time.current)
    grant.invitation_token ||= SecureRandom.urlsafe_base64(24)
    grant.save!
    grant
  end

  def pending?
    user_id.nil?
  end

  def accept!(user)
    update!(user: user, accepted_at: Time.current, invitation_token: nil)
  end

  def display_name
    user&.person&.name || user&.email_address || invited_name.presence || invited_email
  end

  def access_description
    box_office? ? "check people in and sell at the door" : "check people in"
  end

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
