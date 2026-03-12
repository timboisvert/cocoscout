# frozen_string_literal: true

class CocobaseAnswer < ApplicationRecord
  belongs_to :cocobase_submission
  belongs_to :cocobase_field

  has_one_attached :file

  validate :validate_file_content_type, if: -> { file.attached? }
  validate :validate_file_size, if: -> { file.attached? }

  ALLOWED_IMAGE_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze
  ALLOWED_AUDIO_TYPES = %w[audio/mpeg audio/wav audio/aac audio/ogg audio/mp4].freeze
  ALLOWED_CONTENT_TYPES = (ALLOWED_IMAGE_TYPES + ALLOWED_AUDIO_TYPES).freeze
  MAX_FILE_SIZE = 25.megabytes

  def image?
    file.attached? && ALLOWED_IMAGE_TYPES.include?(file.content_type)
  end

  def audio?
    file.attached? && ALLOWED_AUDIO_TYPES.include?(file.content_type)
  end

  def youtube_url?
    value.present? && value.match?(%r{(youtube\.com/watch|youtu\.be/)})
  end

  def spotify_url?
    value.present? && value.match?(%r{(open\.spotify\.com/)})
  end

  def youtube_embed_id
    return unless youtube_url?

    match = value.match(%r{(?:youtube\.com/watch\?v=|youtu\.be/)([\w-]+)})
    match&.[](1)
  end

  def spotify_embed_uri
    return unless spotify_url?

    match = value.match(%r{open\.spotify\.com/(track|album|playlist)/([\w]+)})
    return unless match

    "#{match[1]}/#{match[2]}"
  end

  private

  def validate_file_content_type
    return if ALLOWED_CONTENT_TYPES.include?(file.content_type)

    file.purge
    errors.add(:file, "must be an image (JPEG, PNG, GIF, WebP) or audio file (MP3, WAV, AAC, OGG)")
  end

  def validate_file_size
    return if file.blob.byte_size <= MAX_FILE_SIZE

    file.purge
    errors.add(:file, "must be smaller than 25 MB")
  end
end
