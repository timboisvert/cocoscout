# frozen_string_literal: true

# The four page colors (PageColors) on the box office, a production's
# ticketing, and a date. Each is a #rrggbb hex or blank.
module HasPageColors
  extend ActiveSupport::Concern

  included do
    before_validation :normalize_page_colors
    PageColors::FIELDS.each_value do |column|
      validates column, format: { with: PageColors::HEX, message: "must be a color like #ec4899" }, allow_nil: true
    end
  end

  def page_colors_hash
    PageColors::FIELDS.transform_values { |column| self[column] }.compact
  end

  # Any of the four set: on a production or a date, the override is on.
  def own_page_colors?
    page_colors_hash.any?
  end

  # The four columns, from a form's colors; nil clears them all.
  def self.attributes_from(colors)
    PageColors::FIELDS.to_h { |key, column| [ column, colors && PageColors.normalize(colors[key] || colors[column]) ] }
  end

  private

  def normalize_page_colors
    PageColors::FIELDS.each_value { |column| self[column] = PageColors.normalize(self[column]) if has_attribute?(column) }
  end
end
