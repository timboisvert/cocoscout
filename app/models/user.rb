class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  has_many :user_roles, dependent: :destroy
  has_many :production_companies, through: :user_roles

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  validates :email_address, presence: true, uniqueness: { case_sensitive: false }

  def role_for_company(company)
    user_roles.find_by(production_company_id: company.id)&.role
  end
end
