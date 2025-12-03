class Poster < ApplicationRecord
  include HierarchicalStorageKey

  belongs_to :production

  has_one_attached :image, dependent: :purge_later do |attachable|
      attachable.variant :small, resize_to_limit: [ 200, 300 ], preprocessed: true
  end

  validates :name, length: { maximum: 255 }, allow_blank: true
  validate :image_content_type

  after_create :set_as_primary_if_only_poster
  before_validation :unset_other_primaries, if: :will_save_change_to_is_primary?

  scope :primary, -> { where(is_primary: true) }

  def safe_image_variant(variant_name)
    return nil unless image.attached?
    image.variant(variant_name)
  rescue ActiveStorage::InvariableError, ActiveStorage::FileNotFoundError => e
    Rails.logger.error("Failed to generate variant for poster #{id} image: #{e.message}")
    nil
  end

  private

  def image_content_type
    if image.attached? && !image.content_type.in?(%w[image/jpeg image/jpg image/png])
      errors.add(:image, "Poster must be a JPEG, JPG, or PNG file")
    end
  end

  def set_as_primary_if_only_poster
    if production.posters.count == 1
      update_column(:is_primary, true)
    end
  end

  def unset_other_primaries
    if is_primary?
      production.posters.where(is_primary: true).where.not(id: id).update_all(is_primary: false)
    end
  end
end
