# frozen_string_literal: true

class User < ApplicationRecord
  # Multi-profile support: users can have multiple person profiles
  has_many :people, dependent: :nullify
  belongs_to :default_person, class_name: "Person", optional: true

  has_secure_password

  # Override default password reset token expiry (default is 15 minutes, we want 2 hours)
  # The block invalidates the token when password_digest changes (i.e., when password is reset)
  generates_token_for :password_reset, expires_in: 2.hours do
    password_digest
  end

  has_many :sessions, dependent: :destroy

  has_many :organization_roles, dependent: :destroy
  has_many :organizations, through: :organization_roles
  has_many :production_permissions, dependent: :destroy
  has_many :email_logs, dependent: :destroy
  has_many :audition_request_votes, dependent: :destroy
  has_many :audition_votes, dependent: :destroy

  # Message subscriptions - threads the user is subscribed to
  has_many :message_subscriptions, dependent: :destroy
  has_many :subscribed_threads, through: :message_subscriptions, source: :message

  # Messaging - messages addressed to any of user's People
  def received_messages
    person_ids = people.pluck(:id)
    Message.joins(:message_recipients).where(message_recipients: { recipient_type: "Person", recipient_id: person_ids })
  end

  def unread_message_count
    # Sum unread counts across all active subscriptions (optimized via counter cache)
    message_subscriptions.active.sum(:unread_count)
  end

  # Get root messages for threads user is subscribed to
  def subscribed_message_threads
    Message.where(id: message_subscriptions.active.pluck(:message_id))
  end

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  validates :email_address, presence: true, uniqueness: { case_sensitive: false },
                            format: { with: URI::MailTo::EMAIL_REGEXP, message: "must be a valid email address" }
  validates :password, length: { minimum: 8, maximum: 72, message: "must be between 8 and 72 characters" },
                       format: { with: /\A\S.*\S\z|\A\S\z/, message: "cannot be only whitespace" },
                       if: -> { password.present? }
  validate :password_complexity, if: -> { password.present? }
  validate :email_not_malicious

  SUPERADMIN_EMAILS = [ "boisvert@gmail.com", "andiewonnacott@gmail.com" ].freeze

  # Generate a secure random password that meets complexity requirements
  # (uppercase, lowercase, number, special character)
  def self.generate_secure_password
    "#{SecureRandom.hex(8)}A!1a"
  end

  # Returns the user's primary person profile
  # Priority: default_person if set, otherwise the first active profile by creation date
  def primary_person
    default_person || people.where(archived_at: nil).order(:created_at).first
  end

  # Backward compatibility alias - returns the primary person profile
  # This allows existing code using Current.user.person to continue working
  def person
    primary_person
  end

  # Assign a person as the default profile
  def set_default_person!(person)
    return unless people.include?(person)

    update!(default_person: person)
  end

  def email_not_malicious
    return if email_address.blank?

    # Reject emails with special characters commonly used in injection attacks
    if email_address.match?(/[\x00-\x1f\x7f<>"'`\\;|&$(){}\[\]]/)
      errors.add(:email_address, "contains invalid characters")
    end
    # Reject emails that look like command injection attempts (whole words only)
    return unless email_address.match?(/\b(bin|cat|etc|passwd|wget|curl|bash|exec|eval)\b/i)

    errors.add(:email_address, "is not valid")
  end

  def can_manage?
    organization_roles.any?
  end

  # Returns the role for the current organization (default role)
  def default_role
    return nil unless Current.organization

    organization_roles.find_by(organization_id: Current.organization.id)&.company_role
  end

  # Check if user has any access to the current organization
  def has_access_to_current_company?
    return false unless Current.organization

    role = default_role
    # User has access if they have manager/viewer role, OR if they have "member" role with per-production permissions
    return true if %w[manager viewer].include?(role)

    # Check for production-specific permissions
    if role == "member"
      return true if production_permissions.joins(:production)
                                           .where(productions: { organization_id: Current.organization.id })
                                           .exists?
    end

    # Check if user is a reviewer for any active audition cycle in the org
    return true if reviewer_for_any_active_audition_cycle?

    false
  end

  # Returns the effective role for a specific production
  # Checks production-specific permission first, falls back to default role
  def role_for_production(production)
    return nil unless production

    # Check for production-specific permission
    production_permission = production_permissions.find_by(production_id: production.id)
    return production_permission.role if production_permission

    # Fall back to default role if not 'member'
    default = default_role
    default == "member" ? nil : default
  end

  # Check if user is manager for a specific production
  def manager_for_production?(production)
    role_for_production(production) == "manager"
  end

  # Legacy method - checks default role for the organization
  def manager?
    default_role == "manager"
  end

  # Returns all productions the user has access to in the current organization
  # Eager loads logo attachments for efficient rendering in navigation
  def accessible_productions
    return Production.none unless Current.organization

    # If user has manager or viewer as default role, they have access to all productions
    role = default_role
    if %w[manager viewer].include?(role)
      Current.organization.productions.includes(logo_attachment: :blob)
    else
      # Combine production permissions and reviewer access
      permission_production_ids = production_permissions.where(
        production_id: Current.organization.productions.pluck(:id)
      ).pluck(:production_id)

      reviewer_production_ids = productions_with_reviewer_access.pluck(:id)

      all_production_ids = (permission_production_ids + reviewer_production_ids).uniq
      Current.organization.productions.where(id: all_production_ids).includes(logo_attachment: :blob)
    end
  end

  # Returns productions where user is a reviewer for an active audition cycle
  def productions_with_reviewer_access
    return Production.none unless person
    return Production.none unless Current.organization

    # Collect all production IDs where user has reviewer access
    production_ids = []

    # 1. Productions where user is explicitly listed as a reviewer
    specific_reviewer_ids = Production.joins(audition_cycles: :audition_reviewers)
                                      .where(organization_id: Current.organization.id)
                                      .where(audition_cycles: { active: true })
                                      .where(audition_reviewers: { person_id: person.id })
                                      .pluck(:id)
    production_ids.concat(specific_reviewer_ids)

    # 2. Productions where reviewer_access_type is 'all' and user is in talent pool
    talent_pool_production_ids = person.talent_pool_productions
                                       .where(organization_id: Current.organization.id)
                                       .joins(:audition_cycles)
                                       .where(audition_cycles: { active: true, reviewer_access_type: "all" })
                                       .pluck(:id)
    production_ids.concat(talent_pool_production_ids)

    # 3. Productions where reviewer_access_type is 'managers' and user has production team access
    team_production_ids = productions_with_team_access
                          .where(organization_id: Current.organization.id)
                          .joins(:audition_cycles)
                          .where(audition_cycles: { active: true, reviewer_access_type: "managers" })
                          .pluck(:id)
    production_ids.concat(team_production_ids)

    Production.where(id: production_ids.uniq)
  end

  # Check if user is a reviewer for any active audition cycle in the current org
  def reviewer_for_any_active_audition_cycle?
    productions_with_reviewer_access.exists?
  end

  # Check if user can review a specific audition cycle
  def can_review_audition_cycle?(audition_cycle)
    return false unless audition_cycle
    return true if role_for_production(audition_cycle.production).present?

    case audition_cycle.reviewer_access_type
    when "managers"
      # Only production team members (managers/viewers) - already checked above
      false
    when "all"
      # Anyone in the talent pool
      person&.in_talent_pool_for?(audition_cycle.production)
    when "specific"
      # Only specific reviewers
      person && audition_cycle.reviewer_people.include?(person)
    else
      false
    end
  end

  # Helper: productions where user has team access (global or production-specific)
  def productions_with_team_access
    role = default_role
    if %w[manager viewer].include?(role)
      Current.organization.productions
    else
      Production.where(id: production_permissions.select(:production_id))
    end
  end

  def superadmin?
    SUPERADMIN_EMAILS.include?(email_address.to_s.downcase)
  end

  # Notification preferences - all default to true (opted in)
  NOTIFICATION_PREFERENCE_KEYS = %w[
    vacancy_invitations
    audition_invitations
    group_invitations
    shoutouts
    message_digest
  ].freeze

  def notification_enabled?(key)
    # Default to true if not explicitly set to false
    notification_preferences[key.to_s] != false
  end

  def set_notification_preference(key, enabled)
    self.notification_preferences = notification_preferences.merge(key.to_s => enabled)
  end

  # SMS Notification Support
  # SMS preferences are stored in notification_preferences jsonb:
  #   - sms_enabled: master toggle
  #   - sms_show_cancellation: show cancellation texts
  #   - sms_vacancy_notification: vacancy invitation texts

  SMS_NOTIFICATION_TYPES = %w[show_cancellation vacancy_notification].freeze

  # Check if phone number has been verified
  def phone_verified?
    phone_verified_at.present? && person&.phone.present?
  end

  # Check if verification is pending
  def phone_verification_pending?
    phone_pending_verification.present? && phone_verification_sent_at.present? && phone_verification_sent_at > 10.minutes.ago
  end

  # Check if SMS is fully enabled (has verified phone and master toggle on)
  def sms_enabled?
    phone = person&.phone
    phone.present? && phone_verified? && notification_preferences["sms_enabled"] != false
  end

  # Check if a specific SMS notification type is enabled
  def sms_notification_enabled?(type)
    return false unless sms_enabled?

    notification_preferences["sms_#{type}"] != false
  end

  # Get phone number from primary person profile
  def sms_phone
    person&.phone
  end

  # Get formatted phone for display
  def formatted_sms_phone
    phone = sms_phone
    return nil unless phone.present?

    digits = phone.gsub(/\D/, "")
    return phone unless digits.length == 10

    "(#{digits[0..2]}) #{digits[3..5]}-#{digits[6..9]}"
  end

  # Announcement Dismissal Support
  # Tracks which announcements the user has dismissed via dismissed_announcements jsonb array

  def announcement_dismissed?(announcement_id)
    dismissed_announcements.include?(announcement_id.to_s)
  end

  def dismiss_announcement!(announcement_id)
    return if announcement_dismissed?(announcement_id)

    self.dismissed_announcements = dismissed_announcements + [ announcement_id.to_s ]
    save!
  end

  # Generate an invitation token for setting password
  def generate_invitation_token
    self.invitation_token = SecureRandom.urlsafe_base64(32)
    self.invitation_sent_at = Time.current
    save!
  end

  # Check if invitation token is still valid
  def invitation_token_valid?
    invitation_token.present?
  end

  private

  def password_complexity
    return unless password.present?

    errors.add(:password, "must include at least one uppercase letter") unless password.match?(/[A-Z]/)
    errors.add(:password, "must include at least one lowercase letter") unless password.match?(/[a-z]/)
    errors.add(:password, "must include at least one number") unless password.match?(/[0-9]/)
    errors.add(:password, "must include at least one special character") unless password.match?(/[^A-Za-z0-9]/)
  end
end
