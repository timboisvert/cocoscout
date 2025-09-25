class Location < ApplicationRecord
  belongs_to :production_company
  validates :name, :address1, :city, :state, :postal_code, presence: true
end
