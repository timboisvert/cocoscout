# frozen_string_literal: true

# The wide image (16:9): with the poster (3:4), one of the two pictures every
# production has, and that any show or event can override with its own. Ticket
# pages lead with it (Show#ticket_page_image), and so do shared links.
#
# Shown whole, at its own shape — never cropped. The display variant only
# shrinks it.
module HasWideImage
  extend ActiveSupport::Concern

  WIDE_IMAGE_TYPES = %w[image/jpeg image/jpg image/png image/webp].freeze
  WIDE_IMAGE_MAX_BYTES = 10.megabytes

  included do
    has_one_attached :wide_image, dependent: :purge_later do |attachable|
      attachable.variant :display, resize_to_limit: [ 1600, 1600 ], format: :jpeg, saver: { quality: 85 }, preprocessed: true
    end

    validate :wide_image_is_a_usable_picture
  end

  def safe_wide_image_variant(variant_name = :display)
    return nil unless wide_image.attached?

    wide_image.variant(variant_name)
  rescue ActiveStorage::InvariableError, ActiveStorage::FileNotFoundError => e
    Rails.logger.error("Failed to generate variant for #{self.class.name} #{id} wide image: #{e.message}")
    nil
  end

  private

  def wide_image_is_a_usable_picture
    return unless wide_image.attached? && wide_image.blob

    errors.add(:wide_image, "must be a JPG, PNG or WebP") unless WIDE_IMAGE_TYPES.include?(wide_image.blob.content_type)
    errors.add(:wide_image, "must be 10 MB or smaller") if wide_image.blob.byte_size > WIDE_IMAGE_MAX_BYTES
  end
end
