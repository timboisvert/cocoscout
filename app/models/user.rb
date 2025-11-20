  class User < ApplicationRecord
    has_one :person, dependent: :nullify
    has_secure_password
    has_many :sessions, dependent: :destroy

    has_many :organization_roles, dependent: :destroy
    has_many :organizations, through: :organization_roles
    has_many :production_permissions, dependent: :destroy
    has_many :email_logs, dependent: :destroy

    normalizes :email_address, with: ->(e) { e.strip.downcase }
    validates :email_address, presence: true, uniqueness: { case_sensitive: false },
              format: { with: URI::MailTo::EMAIL_REGEXP, message: "must be a valid email address" }
    validates :password, length: { minimum: 8, message: "must be at least 8 characters" }, if: -> { password.present? }
    validate :email_not_malicious

    def email_not_malicious
      return if email_address.blank?
      # Reject emails with special characters commonly used in injection attacks
      if email_address.match?(/[\x00-\x1f\x7f<>"'`\\;|&$(){}\[\]]/)
        errors.add(:email_address, "contains invalid characters")
      end
      # Reject emails that look like command injection attempts
      if email_address.match?(/(bin|cat|etc|passwd|wget|curl|bash|sh|exec|eval)/i)
        errors.add(:email_address, "is not valid")
      end
    end

    GOD_MODE_EMAILS = [ "boisvert@gmail.com", "andiewonnacott@gmail.com" ].freeze

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
      # User has access if they have manager/viewer role, OR if they have "none" but have per-production permissions
      return true if role == "manager" || role == "viewer"
      return false if role.nil?
      # If role is "none", check if they have any production-specific permissions
      if role == "none"
        production_permissions.joins(:production)
          .where(productions: { organization_id: Current.organization.id })
          .exists?
      else
        false
      end
    end

    # Returns the effective role for a specific production
    # Checks production-specific permission first, falls back to default role
    def role_for_production(production)
      return nil unless production

      # Check for production-specific permission
      production_permission = production_permissions.find_by(production_id: production.id)
      return production_permission.role if production_permission

      # Fall back to default role if not 'none'
      default = default_role
      default == "none" ? nil : default
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
    def accessible_productions
      return Production.none unless Current.organization

      # If user has manager or viewer as default role, they have access to all productions
      role = default_role
      if role == "manager" || role == "viewer"
        Current.organization.productions
      else
        # Otherwise, only return productions they have specific permissions for
        production_ids = production_permissions.where(
          production_id: Current.organization.productions.pluck(:id)
        ).pluck(:production_id)
        Current.organization.productions.where(id: production_ids)
      end
    end

    def god?
      GOD_MODE_EMAILS.include?(email_address.to_s.downcase)
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
  end
