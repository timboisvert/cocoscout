# frozen_string_literal: true

module MessagesHelper
  # Safely render image variants - SVGs can't be transformed by ActiveStorage
  def safe_image_tag(img, variant_options, html_options = {})
    if img.content_type == "image/svg+xml"
      image_tag(img, **html_options)
    else
      image_tag(img.variant(variant_options), **html_options)
    end
  end
end
