# frozen_string_literal: true

# The attached file behind a file_upload-type question answer, shared by
# QuestionnaireAnswer and Answer (audition requests). Accepts images, audio,
# and documents; files land under the hierarchical storage layout (see
# StorageKeyGeneratorService for each record's path).
module QuestionFileUpload
  extend ActiveSupport::Concern

  ALLOWED_AUDIO_TYPES = %w[audio/mpeg audio/wav audio/aac audio/ogg audio/mp4].freeze
  ALLOWED_IMAGE_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze
  ALLOWED_DOCUMENT_TYPES = %w[
    application/pdf
    application/msword
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
    text/plain
  ].freeze
  ALLOWED_FILE_TYPES = (ALLOWED_AUDIO_TYPES + ALLOWED_IMAGE_TYPES + ALLOWED_DOCUMENT_TYPES).freeze
  MAX_FILE_SIZE = 25.megabytes

  # What the <input accept=...> should offer — keep in sync with the list above.
  ACCEPT_ATTRIBUTE = ALLOWED_FILE_TYPES.join(",")

  included do
    include HierarchicalStorageKey

    has_one_attached :file

    validate :validate_file_attachment
  end

  # Media type detection for attached files (drives how the answer renders).
  def image?
    file.attached? && file.content_type.in?(ALLOWED_IMAGE_TYPES)
  end

  def audio?
    file.attached? && file.content_type.in?(ALLOWED_AUDIO_TYPES)
  end

  def document?
    file.attached? && file.content_type.in?(ALLOWED_DOCUMENT_TYPES)
  end

  private

  def validate_file_attachment
    return unless file.attached?

    unless file.content_type.in?(ALLOWED_FILE_TYPES)
      errors.add(:file, "must be an image (JPEG, PNG, GIF, WebP), audio file (MP3, WAV, AAC, OGG, MP4), or document (PDF, Word, plain text)")
    end

    if file.byte_size > MAX_FILE_SIZE
      errors.add(:file, "must be less than 25MB")
    end
  end
end
