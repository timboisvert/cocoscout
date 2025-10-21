class Location < ApplicationRecord
  belongs_to :production_company

  validates :name, :address1, :city, :state, :postal_code, presence: true

  # Ensure only one location is default per production company
  before_save :ensure_single_default
  after_create :set_as_default_if_only_location

  private

  def ensure_single_default
    if default?
      # Unset default for all other locations in the same production company
      Location.where(production_company: production_company).where.not(id: id).update_all(default: false)
    end
  end

  def set_as_default_if_only_location
    if production_company.locations.count == 1
      update_column(:default, true)
    end
  end
end
