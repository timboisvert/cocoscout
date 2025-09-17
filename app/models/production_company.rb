class ProductionCompany < ApplicationRecord
  has_many :productions, dependent: :destroy
  has_and_belongs_to_many :users

  validates :name, presence: true
end
