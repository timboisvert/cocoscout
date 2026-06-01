# frozen_string_literal: true

class CityHubMembership < ApplicationRecord
  belongs_to :city_hub
  belongs_to :user

  enum :role, { editor: 0, viewer: 1 }, prefix: :role
end
