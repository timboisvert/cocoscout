# frozen_string_literal: true

# Someone the theater lets watch a show's ticket sales without being a
# manager — a producer, a performer, a friend of the show: sold of capacity,
# sales, the guest list as names only. Shared for one show (scope: a
# TicketListing) or every date of a production (scope: a Production).
#
# Like a door grant: an invitation by email waits on its token until the
# person signs in or makes an account; a revocation is kept, not deleted.
# A contract's contractor needs no row (TicketSalesAccess).
class TicketSalesViewer < ApplicationRecord
  SCOPES = %w[TicketListing Production].freeze

  belongs_to :organization
  belongs_to :user, optional: true
  belongs_to :scope, polymorphic: true
  belongs_to :granted_by, class_name: "User", optional: true
  belongs_to :revoked_by, class_name: "User", optional: true

  normalizes :invited_email, with: ->(email) { email.to_s.strip.downcase.presence }

  validates :scope_type, inclusion: { in: SCOPES }
  validates :invited_email, format: { with: URI::MailTo::EMAIL_REGEXP }, if: -> { user_id.nil? }
  validate :scope_belongs_to_organization

  scope :active, -> { where(revoked_at: nil) }
  scope :pending_invites, -> { active.where(user_id: nil) }

  def self.invite!(organization:, email:, name:, scope:, by:)
    viewer = organization.ticket_sales_viewers.pending_invites.find_or_initialize_by(invited_email: email.to_s.strip.downcase, scope: scope)
    viewer.assign_attributes(invited_name: name.to_s.squish.presence, granted_by: by, invited_at: Time.current)
    viewer.invitation_token ||= SecureRandom.urlsafe_base64(24)
    viewer.save!
    viewer
  end

  def accept!(user)
    update!(user: user, accepted_at: Time.current, invitation_token: nil)
  end

  def revoke!(by)
    update!(revoked_at: Time.current, revoked_by: by)
  end

  def pending?
    user_id.nil?
  end

  def revoked?
    revoked_at.present?
  end

  def display_name
    user&.person&.name || user&.email_address || invited_name.presence || invited_email
  end

  # "Rising Stars, every date" / "Rising Stars · Fri Oct 10".
  def scope_label
    case scope
    when Production then "#{scope.name}, every date"
    when TicketListing then "#{scope.display_title} · #{scope.show.date_and_time.strftime('%a %b %-d')}"
    end
  end

  private

  def scope_belongs_to_organization
    owner = scope.is_a?(Production) ? scope.organization_id : scope&.organization_id
    errors.add(:scope, "belongs to another organization") if owner && owner != organization_id
  end
end
