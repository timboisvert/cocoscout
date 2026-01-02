# frozen_string_literal: true

# Cleans up orphaned S3 files that no longer have corresponding blob records.
# This happens after blob keys are migrated - the old flat-key files remain on S3.
#
# SAFETY MEASURES:
# 1. Only deletes files older than 7 days (avoids race conditions with in-progress uploads)
# 2. Verifies the file is truly orphaned (no blob record with that key)
# 3. Logs everything for audit trail
# 4. Has dry_run mode to preview what would be deleted
#
# Run manually with: CleanupOrphanedS3FilesJob.perform_later(dry_run: true)
#
class CleanupOrphanedS3FilesJob < ApplicationJob
  queue_as :default

  # Only delete files older than this many days
  MINIMUM_AGE_DAYS = 7

  def perform(dry_run: false)
    deleted = 0
    skipped = 0
    too_new = 0
    errors = 0

    service = ActiveStorage::Blob.service
    unless service.respond_to?(:bucket)
      Rails.logger.info("[CleanupOrphanedS3FilesJob] Skipping - not using S3 service")
      return
    end

    bucket = service.bucket
    db_keys = Set.new(ActiveStorage::Blob.where(service_name: "amazon").pluck(:key))
    cutoff_time = MINIMUM_AGE_DAYS.days.ago

    Rails.logger.info("[CleanupOrphanedS3FilesJob] Starting cleanup (dry_run: #{dry_run})")
    Rails.logger.info("[CleanupOrphanedS3FilesJob] #{db_keys.size} blobs in database")
    Rails.logger.info("[CleanupOrphanedS3FilesJob] Only deleting files older than #{cutoff_time}")

    processed = 0
    bucket.objects.each do |object|
      key = object.key

      # Skip if this key exists in database - it's an active file
      if db_keys.include?(key)
        skipped += 1
        processed += 1
        next
      end

      # Skip if file was modified recently - might be in-progress upload
      if object.last_modified > cutoff_time
        too_new += 1
        processed += 1
        Rails.logger.debug("[CleanupOrphanedS3FilesJob] Skipping (too new): #{key}")
        next
      end

      # This file is orphaned and old enough to delete
      if dry_run
        Rails.logger.info("[CleanupOrphanedS3FilesJob] Would delete: #{key} (last modified: #{object.last_modified})")
      else
        begin
          object.delete
          Rails.logger.info("[CleanupOrphanedS3FilesJob] Deleted: #{key}")
        rescue StandardError => e
          Rails.logger.error("[CleanupOrphanedS3FilesJob] Failed to delete #{key}: #{e.message}")
          errors += 1
          processed += 1
          next
        end
      end
      deleted += 1

      processed += 1
      if (processed % 500).zero?
        Rails.logger.info("[CleanupOrphanedS3FilesJob] Progress: #{processed} objects scanned...")
      end
    end

    Rails.logger.info(
      "[CleanupOrphanedS3FilesJob] Completed: " \
      "#{deleted} #{dry_run ? 'would be ' : ''}deleted, " \
      "#{skipped} active (kept), " \
      "#{too_new} too new (kept), " \
      "#{errors} errors"
    )
  end
end
