  class User < ApplicationRecord
    has_one :person, dependent: :nullify
    has_secure_password
    has_many :sessions, dependent: :destroy

    has_many :user_roles, dependent: :destroy
    has_many :production_companies, through: :user_roles
    has_many :production_permissions, dependent: :destroy

    normalizes :email_address, with: ->(e) { e.strip.downcase }
    validates :email_address, presence: true, uniqueness: { case_sensitive: false }

    GOD_MODE_EMAILS = [ "boisvert@gmail.com" ].freeze

    def can_manage?
      user_roles.any?
    end

    # Returns the role for the current production company (default role)
    def default_role
      return nil unless Current.production_company
      user_roles.find_by(production_company_id: Current.production_company.id)&.company_role
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

    # Legacy method - checks default role for the production company
    def manager?
      default_role == "manager"
    end

    # Returns all productions the user has access to in the current production company
    def accessible_productions
      return Production.none unless Current.production_company

      # If user has manager or viewer as default role, they have access to all productions
      role = default_role
      if role == "manager" || role == "viewer"
        Current.production_company.productions
      else
        # Otherwise, only return productions they have specific permissions for
        production_ids = production_permissions.where(
          production_id: Current.production_company.productions.pluck(:id)
        ).pluck(:production_id)
        Current.production_company.productions.where(id: production_ids)
      end
    end

    def god?
      GOD_MODE_EMAILS.include?(email_address.to_s.downcase)
    end
  end
