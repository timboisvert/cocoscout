class ShowLink < ApplicationRecord
  belongs_to :show
  validates :url, presence: true
end
