# frozen_string_literal: true

# Migrates Active Storage blobs from flat keys to hierarchical keys.
# Run with: MigrateStorageKeysJob.perform_later
# Or for a specific batch size: MigrateStorageKeysJob.perform_later(batch_size: 100)
#
class MigrateStorageKeysJob < ApplicationJob
  queue_as :default

  def perform(batch_size: 50)
    migrated = 0
    failed = 0
    skipped = 0

    # Find blobs with flat keys (no /) that have attachments
    flat_blobs = ActiveStorage::Blob
      .where("key NOT LIKE '%/%'")
      .joins(:attachments)
      .distinct
      .limit(batch_size)

    flat_blobs.find_each do |blob|
      result = migrate_blob(blob)
      case result
      when :migrated then migrated += 1
      when :failed then failed += 1
      when :skipped then skipped += 1
      end
    end

    Rails.logger.info(
      "[MigrateStorageKeysJob] Completed: #{migrated} migrated, #{failed} failed, #{skipped} skipped"
    )

    # Log remaining count
    remaining = ActiveStorage::Blob.where("key NOT LIKE '%/%'").joins(:attachments).distinct.count
    if remaining > 0
      Rails.logger.info("[MigrateStorageKeysJob] #{remaining} blobs remaining")
    else
      Rails.logger.info("[MigrateStorageKeysJob] All blobs migrated!")
    end
  end

  private

  def migrate_blob(blob)
    attachment = blob.attachments.first
    return :skipped unless attachment

    # Generate the new hierarchical key
    new_key = generate_hierarchical_key(attachment, blob)
    return :skipped if new_key.nil? || new_key == blob.key || !new_key.include?("/")

    # Copy file to new key
    copy_to_new_key(blob, new_key)

    # Update the blob record
    old_key = blob.key
    blob.update_column(:key, new_key)

    Rails.logger.info("[MigrateStorageKeysJob] Migrated blob #{blob.id}: #{old_key} -> #{new_key}")
    :migrated
  rescue StandardError => e
    Rails.logger.error("[MigrateStorageKeysJob] Failed to migrate blob #{blob.id}: #{e.message}")
    :failed
  end

  def generate_hierarchical_key(attachment, blob)
    record = attachment.record
    attachment_name = attachment.name

    case record
    when ActiveStorage::VariantRecord
      # Variant records belong to a parent blob, use that blob's key as base
      parent_blob = record.blob
      parent_attachment = parent_blob.attachments.first
      return nil unless parent_attachment

      parent_key = parent_blob.key
      # If parent already has hierarchical key, use it as prefix
      if parent_key.include?("/")
        "#{parent_key}/variants/#{blob.key}"
      else
        # Parent also needs migration, skip for now
        nil
      end
    when ActiveStorage::Blob
      # Preview image for a blob
      parent_attachment = record.attachments.first
      return nil unless parent_attachment

      parent_key = record.key
      if parent_key.include?("/")
        "#{parent_key}/previews/#{blob.key}"
      else
        nil
      end
    else
      # Regular attachment - use the service
      StorageKeyGeneratorService.generate_key_for_attachment(attachment, blob)
    end
  end

  def copy_to_new_key(blob, new_key)
    service = blob.service

    if service.respond_to?(:bucket)
      # S3 service - use copy
      service.bucket.object(new_key).copy_from(
        copy_source: "#{service.bucket.name}/#{blob.key}"
      )
    else
      # Disk service - download and re-upload
      data = blob.download
      service.upload(new_key, StringIO.new(data), checksum: blob.checksum)
    end
  end
end
