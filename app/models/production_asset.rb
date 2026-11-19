# frozen_string_literal: true

# What a production has for one of its organization's AssetSpecs, or a file
# of its own that matches none (an additional file, asset_spec_id nil: any
# size, never part of a request).
#
# For the built-ins the picture or words live where the app already reads
# them (the primary Poster, the production's wide image, its description),
# and this row only remembers who added it and when. For every other item it
# holds the file or the words itself.
class ProductionAsset < ApplicationRecord
  include HierarchicalStorageKey

  ADDITIONAL_MAX_BYTES = 100.megabytes

  belongs_to :production
  belongs_to :asset_spec, optional: true
  belongs_to :asset_request, optional: true
  belongs_to :uploaded_by_user, class_name: "User", optional: true

  has_one_attached :file, dependent: :purge_later do |attachable|
    attachable.variant :small, resize_to_limit: [ 480, 480 ], format: :jpeg, saver: { quality: 80 }
  end

  scope :additional, -> { where(asset_spec_id: nil) }

  validates :name, presence: true, length: { maximum: 120 }, if: -> { asset_spec_id.nil? }
  validate :additional_file_present, if: -> { asset_spec_id.nil? }

  def additional? = asset_spec_id.nil?

  # A small picture of the file: images and PDFs, when it can be made.
  def preview
    return nil unless file.attached?
    return file.variant(:small) if file.variable?
    return file.preview(resize_to_limit: [ 480, 480 ]) if file.previewable?

    nil
  rescue ActiveStorage::InvariableError, ActiveStorage::UnpreviewableError, ActiveStorage::FileNotFoundError
    nil
  end

  def file_words
    return nil unless file.attached?

    parts = []
    parts << "#{width} × #{height}" if width && height
    ext = File.extname(file.filename.to_s).delete(".").upcase.presence
    parts << ext if ext
    parts << ActiveSupport::NumberHelper.number_to_human_size(file.byte_size) if additional?
    parts.join(", ")
  end

  def uploaded_words
    who = uploaded_by_name.presence || uploaded_by_user&.person&.name || (asset_request ? "someone with the link" : nil)
    when_words = (changed_at || updated_at)
    date = when_words&.to_date == Date.current ? "today at #{when_words.strftime('%-l:%M %p')}" : "on #{when_words&.strftime('%B %-d')}"
    verb = last_change == "replaced" ? "Replaced" : "Added"
    who ? "#{verb} by #{who} #{date}" : "#{verb} #{date}"
  end

  private

  def additional_file_present
    errors.add(:file, "must be chosen") unless file.attached?
    errors.add(:file, "must be 100 MB or smaller") if file.attached? && file.blob.byte_size > ADDITIONAL_MAX_BYTES
  end
end
