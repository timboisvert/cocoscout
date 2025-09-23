class User < ApplicationRecord
  has_one :person, dependent: :nullify
  has_secure_password
  has_many :sessions, dependent: :destroy

  has_many :user_roles, dependent: :destroy
  has_many :production_companies, through: :user_roles

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  validates :email_address, presence: true, uniqueness: { case_sensitive: false }

  def can_manage?
    user_roles.any?
  end

  def role
    user_roles.find_by(production_company_id: Current.production_company.id)&.role
  end

  def admin?
    role == "admin"
  end
end
