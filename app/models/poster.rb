class Poster < ApplicationRecord
  belongs_to :production

  has_one_attached :image, dependent: :purge_later do |attachable|
      attachable.variant :small, resize_to_limit: [ 200, 300 ], preprocessed: true
  end

  validates :name, length: { maximum: 255 }, allow_blank: true
end
