# frozen_string_literal: true

# One of the images or written items an organization expects every
# production to have (Organization settings → Visual Assets; Tim,
# 2026-11-19). Three are built in and can't be removed: the Poster and the
# Wide image (the app's own pages are drawn for their shapes, so the shape
# stays; the name, smallest size, and note can change) and the Show
# description (it is the production's description). The organization adds
# the rest: an Eventbrite banner, a lobby TV, an Instagram square, a print
# poster, a short blurb.
#
# An image is a shape and a smallest size in pixels (width × height); a
# bigger file of the same shape is fine. A print size keeps its DPI, so it
# can be shown as inches. AssetCheck holds a file to it.
class AssetSpec < ApplicationRecord
  KINDS = %w[image text].freeze
  BUILTINS = %w[poster wide description].freeze
  FORMATS = { "jpg" => %w[image/jpeg image/jpg], "png" => %w[image/png], "webp" => %w[image/webp], "pdf" => %w[application/pdf] }.freeze
  FORMAT_LABELS = { "jpg" => "JPG", "png" => "PNG", "webp" => "WebP", "pdf" => "PDF" }.freeze
  # The built-ins' shapes are the app's, and the formats their records take
  # (Poster: JPG or PNG; HasWideImage: JPG, PNG, or WebP).
  BUILTIN_DEFAULTS = {
    "poster" => { name: "Poster", kind: "image", width: 1080, height: 1440, formats: %w[jpg png], max_megabytes: 10,
                  used_for: "Lists and public pages across CocoScout" },
    "wide" => { name: "Wide image", kind: "image", width: 1280, height: 720, formats: %w[jpg png webp], max_megabytes: 10,
                used_for: "Ticket pages and shared links" },
    "description" => { name: "Show description", kind: "text", max_length: 2000,
                       used_for: "The production's description, on its ticket pages and public page" }
  }.freeze
  BUILTIN_FORMATS = { "poster" => %w[jpg png], "wide" => %w[jpg png webp] }.freeze
  MAX_MEGABYTES = 100

  belongs_to :organization
  has_many :production_assets, dependent: :nullify

  scope :active, -> { where(archived_at: nil) }
  scope :ordered, -> { order(:position, :id) }
  scope :images, -> { where(kind: "image") }
  scope :texts, -> { where(kind: "text") }

  validates :name, presence: true, length: { maximum: 80 }
  validates :kind, inclusion: { in: KINDS }
  validates :builtin, inclusion: { in: BUILTINS }, allow_nil: true
  validates :width, :height, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 20_000 }, if: :image?
  validates :dpi, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 2400 }, allow_nil: true
  validates :max_megabytes, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_MEGABYTES }
  validates :max_length, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 10_000 }, allow_nil: true
  validates :used_for, length: { maximum: 120 }
  validates :guidance, length: { maximum: 500 }
  validate :formats_are_known, if: :image?
  validate :builtin_shape_kept, if: -> { builtin.in?(%w[poster wide]) }

  # The organization's list, with the three built-ins made the first time
  # anyone looks (no migration runs app code for them).
  def self.for(organization)
    ensure_builtins!(organization)
    organization.asset_specs.active.ordered
  end

  def self.ensure_builtins!(organization)
    existing = organization.asset_specs.where.not(builtin: nil).pluck(:builtin)
    missing = BUILTINS - existing
    return if missing.empty?

    BUILTINS.each_with_index do |key, index|
      next unless missing.include?(key)

      position = key == "description" ? (organization.asset_specs.maximum(:position) || 0) + 1 : index - 2
      organization.asset_specs.create!(BUILTIN_DEFAULTS.fetch(key).merge(builtin: key, position: position, required: true))
    rescue ActiveRecord::RecordNotUnique
      next
    end
  end

  def image? = kind == "image"
  def text? = kind == "text"
  def builtin? = builtin.present?
  def removable? = !builtin?

  # "3:4", "16:9", "11:17", "1:1".
  def ratio_label
    return nil unless image? && width.to_i.positive? && height.to_i.positive?

    divisor = width.gcd(height)
    a = width / divisor
    b = height / divisor
    return "#{a}:#{b}" if [ a, b ].max <= 40

    format("%.2f:1", width.to_f / height)
  end

  def square? = image? && width == height

  def format_labels = formats.map { |key| FORMAT_LABELS.fetch(key, key.upcase) }
  def content_types = formats.flat_map { |key| FORMATS.fetch(key, []) }

  def print?
    dpi.present?
  end

  def inches(pixels)
    value = pixels.to_f / dpi
    value == value.round ? value.round.to_s : format("%.1f", value)
  end

  # How the size reads everywhere: "16:9, at least 1920 × 1080" or, for a
  # print size, "11 × 17 inches at 300 DPI (3300 × 5100)".
  def size_words
    return nil unless image?
    return "#{inches(width)} × #{inches(height)} inches at #{dpi} DPI (#{width} × #{height})" if print?

    "#{ratio_label}, at least #{width} × #{height}"
  end

  def formats_words
    format_labels.to_sentence(two_words_connector: " or ", last_word_connector: ", or ")
  end

  # The one line under its name: size and file types for an image, the
  # length for a written item.
  def description_line
    if image?
      "#{size_words}. #{formats_words}."
    elsif max_length
      "Up to #{max_length} characters."
    end
  end

  def max_bytes = max_megabytes.megabytes

  # Removing one keeps what productions already have: their files become
  # additional files under its name; written words stay with the item.
  def archive!
    transaction do
      production_assets.where(asset_spec_id: id).find_each do |asset|
        next unless image?

        asset.update!(asset_spec_id: nil, name: asset.name.presence || name)
      end
      update!(archived_at: Time.current)
    end
  end

  private

  def formats_are_known
    if formats.blank?
      errors.add(:formats, "must include at least one file type")
    elsif (formats - FORMATS.keys).any?
      errors.add(:formats, "can only be JPG, PNG, WebP, or PDF")
    elsif builtin.in?(%w[poster wide]) && (formats - BUILTIN_FORMATS.fetch(builtin)).any?
      errors.add(:formats, "can only be #{BUILTIN_FORMATS.fetch(builtin).map { |key| FORMAT_LABELS[key] }.to_sentence(last_word_connector: ', or ', two_words_connector: ' or ')} for the #{BUILTIN_DEFAULTS.dig(builtin, :name)}")
    end
  end

  # The poster is 3:4 and the wide image 16:9 wherever CocoScout shows them.
  def builtin_shape_kept
    want = builtin == "poster" ? Rational(3, 4) : Rational(16, 9)
    return if width.to_i.positive? && height.to_i.positive? && Rational(width, height) == want

    errors.add(:base, "The #{builtin == 'poster' ? 'poster stays 3:4' : 'wide image stays 16:9'}, because that is how CocoScout shows it")
  end
end
