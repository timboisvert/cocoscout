class ProductionCompany < ApplicationRecord
  has_many :productions, dependent: :destroy
  has_many :invitations, dependent: :destroy
  has_many :user_roles, dependent: :destroy
  has_many :users, through: :user_roles

  validates :name, presence: true
end
