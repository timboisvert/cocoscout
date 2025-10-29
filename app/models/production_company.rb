class ProductionCompany < ApplicationRecord
  has_many :productions, dependent: :destroy
  has_many :team_invitations, dependent: :destroy
  has_many :user_roles, dependent: :destroy
  has_many :users, through: :user_roles
  has_many :locations, dependent: :destroy
  has_and_belongs_to_many :people

  validates :name, presence: true
end
