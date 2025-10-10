class Poster < ApplicationRecord
  belongs_to :production

  has_one_attached :image, dependent: :purge_later do |attachable|
      attachable.variant :small, resize_to_limit: [ 200, 300 ], preprocessed: true
  end

  validates :name, length: { maximum: 255 }, allow_blank: true
  validate :image_content_type

  private

  def image_content_type
    if image.attached? && !image.content_type.in?(%w[image/jpeg image/jpg image/png])
      errors.add(:image, "Poster must be a JPEG, JPG, or PNG file")
    end
  end
end
