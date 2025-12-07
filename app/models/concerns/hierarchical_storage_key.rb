# frozen_string_literal: true

# Migrates blob keys to hierarchical structure after attachment.
#
# Include this concern in models that have Active Storage attachments
# to automatically migrate flat keys to hierarchical keys after upload.
#
# Example:
#   class ProfileHeadshot < ApplicationRecord
#     include HierarchicalStorageKey
#     has_one_attached :image
#   end
#
module HierarchicalStorageKey
  extend ActiveSupport::Concern

  included do
    after_commit :migrate_blob_keys_to_hierarchical, on: %i[create update]
  end

  private

  def migrate_blob_keys_to_hierarchical
    # Get all attachments for this record
    self.class.reflect_on_all_attachments.each do |attachment_reflection|
      attachment_name = attachment_reflection.name
      attachment = public_send(attachment_name)

      next unless attachment.attached?

      # Handle both has_one_attached and has_many_attached
      blobs = if attachment.respond_to?(:blobs)
                attachment.blobs
      else
                [ attachment.blob ].compact
      end

      blobs.each do |blob|
        migrate_blob_if_needed(blob, attachment_name)
      end
    end
  rescue StandardError => e
    # Don't let migration errors break the application
    Rails.logger.error("[HierarchicalStorageKey] Error in migrate_blob_keys_to_hierarchical: #{e.message}")
  end

  def migrate_blob_if_needed(blob, attachment_name)
    # Skip if blob is not persisted
    return unless blob.persisted?

    # Skip if already hierarchical (contains /)
    return if blob.key.include?("/")

    # Skip if not on S3 (optional - remove to also migrate local)
    # return unless blob.service_name == "amazon"

    attachment = blob.attachments.find_by(record: self, name: attachment_name)
    return unless attachment

    new_key = StorageKeyGeneratorService.generate_key_for_attachment(attachment, blob)
    return if new_key.nil? || new_key == blob.key

    # Copy to new key
    begin
      storage_service = blob.service

      if storage_service.respond_to?(:bucket)
        # S3 service
        storage_service.bucket.object(new_key).copy_from(
          copy_source: "#{storage_service.bucket.name}/#{blob.key}"
        )
      else
        # Disk service
        data = blob.download
        storage_service.upload(new_key, StringIO.new(data), checksum: blob.checksum)
      end

      # Update blob record
      blob.update_column(:key, new_key)

      Rails.logger.info("[HierarchicalStorageKey] Migrated blob #{blob.id} from #{blob.key} to #{new_key}")
    rescue StandardError => e
      Rails.logger.error("[HierarchicalStorageKey] Failed to migrate blob #{blob.id}: #{e.message}")
    end
  end
end
