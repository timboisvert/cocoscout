class Location < ApplicationRecord
  validates :name, :address1, :city, :state, :postal_code, presence: true
end
