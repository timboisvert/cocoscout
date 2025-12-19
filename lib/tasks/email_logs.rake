# frozen_string_literal: true

namespace :email_logs do
  desc "Delete obvious duplicate EmailLog records (same recipient, subject, sent_at within 1 second)"
  task delete_duplicates: :environment do
    puts "Finding and deleting duplicate EmailLog records..."

    # Group by recipient + subject + approximate sent_at (within same second)
    duplicates_deleted = 0

    # Use database-agnostic date truncation
    date_trunc_sql = if ActiveRecord::Base.connection.adapter_name.downcase.include?("postgresql")
      "date_trunc('second', sent_at)"
    else
      "strftime('%Y-%m-%d %H:%M:%S', sent_at)"
    end

    EmailLog.select(:recipient, :subject, Arel.sql("#{date_trunc_sql} as sent_second"))
            .group(:recipient, :subject, Arel.sql(date_trunc_sql))
            .having("COUNT(*) > 1")
            .each do |group|
      # Find all records matching this group
      records = EmailLog.where(recipient: group.recipient, subject: group.subject)
                        .where("#{date_trunc_sql} = ?", group.sent_second)
                        .order(:id)

      # Keep the first, delete the rest
      records_to_delete = records.offset(1)
      count = records_to_delete.count
      records_to_delete.destroy_all
      duplicates_deleted += count
    end

    puts "Deleted #{duplicates_deleted} duplicate records"
  end

  desc "Backfill recipient_entity for historical EmailLog records by matching email addresses"
  task backfill_recipient_entities: :environment do
    puts "Starting backfill of recipient_entity for EmailLog records..."

    # Get total count for progress tracking
    total = EmailLog.where(recipient_entity_id: nil).count
    puts "Found #{total} EmailLog records without recipient_entity"

    if total.zero?
      puts "Nothing to backfill!"
      exit
    end

    # Build lookup hashes for faster matching
    puts "Building email lookup tables..."

    person_emails = Person.where.not(email: [ nil, "" ]).pluck(:email, :id).to_h
    puts "  - #{person_emails.size} people with emails"

    group_emails = Group.where.not(email: [ nil, "" ]).pluck(:email, :id).to_h
    puts "  - #{group_emails.size} groups with emails"

    # Process in batches
    updated_count = 0
    matched_count = 0
    batch_size = 1000

    EmailLog.where(recipient_entity_id: nil).find_in_batches(batch_size: batch_size) do |batch|
      batch.each do |log|
        # Handle multi-recipient emails by taking the first one
        recipient_email = log.recipient.split(",").first&.strip

        next if recipient_email.blank?

        # Try to match to a Person first
        if person_emails.key?(recipient_email)
          log.update_columns(
            recipient_entity_type: "Person",
            recipient_entity_id: person_emails[recipient_email]
          )
          matched_count += 1
        # Then try Group
        elsif group_emails.key?(recipient_email)
          log.update_columns(
            recipient_entity_type: "Group",
            recipient_entity_id: group_emails[recipient_email]
          )
          matched_count += 1
        end

        updated_count += 1
      end

      puts "Processed #{updated_count}/#{total} records (#{matched_count} matched)"
    end

    puts ""
    puts "Backfill complete!"
    puts "  - Total processed: #{updated_count}"
    puts "  - Successfully matched: #{matched_count}"
    puts "  - Unmatched (email not found): #{updated_count - matched_count}"
  end

  desc "Backfill email_batch for historical EmailLog records by grouping same subject/time"
  task backfill_email_batches: :environment do
    puts "Starting backfill of email_batch for EmailLog records..."

    # Find email logs that could be batched (same subject, sent within same minute, no batch yet)
    # Note: user_id in EmailLog is the RECIPIENT, not sender, so we don't group by it
    batches_created = 0
    logs_updated = 0

    # Use database-agnostic date truncation
    date_trunc_sql = if ActiveRecord::Base.connection.adapter_name.downcase.include?("postgresql")
      "date_trunc('minute', sent_at)"
    else
      "strftime('%Y-%m-%d %H:%M', sent_at)"
    end

    # Find potential batch groups: same subject, within same minute
    EmailLog.where(email_batch_id: nil)
            .where.not(subject: nil)
            .group(:subject, Arel.sql(date_trunc_sql))
            .having("COUNT(*) > 1")
            .pluck(:subject, Arel.sql(date_trunc_sql))
            .each do |subject, sent_minute|
      # Find all records in this group
      records = EmailLog.where(email_batch_id: nil)
                        .where(subject: subject)
                        .where("#{date_trunc_sql} = ?", sent_minute)

      count = records.count
      next if count <= 1

      # Use the first record's user as the batch owner (or any user if we can find one)
      first_log = records.first
      user = first_log.user

      # If no user on the log, try to find one from the organization
      unless user
        puts "Warning: No user found for batch with subject '#{subject.truncate(40)}', skipping..."
        next
      end

      # Parse the sent_minute back to a time
      sent_at = sent_minute.is_a?(Time) ? sent_minute : (Time.zone.parse(sent_minute.to_s) rescue Time.current)

      # Create a batch for this group
      batch = EmailBatch.create!(
        user: user,
        subject: subject,
        recipient_count: count,
        sent_at: sent_at
      )

      # Update all records in this group
      records.update_all(email_batch_id: batch.id)

      batches_created += 1
      logs_updated += count

      puts "Created batch ##{batch.id}: #{count} emails with subject '#{subject.truncate(50)}'"
    end

    puts ""
    puts "Backfill complete!"
    puts "  - Batches created: #{batches_created}"
    puts "  - Email logs updated: #{logs_updated}"
  end

  desc "Migrate email_logs.body column to Active Storage attachments"
  task migrate_to_active_storage: :environment do
    puts "Migrating email_logs body column to Active Storage..."

    # Check if body column still exists
    unless EmailLog.column_names.include?("body")
      puts "Body column no longer exists. Migration already complete or column removed."
      exit 0
    end

    total = EmailLog.where.not(body: nil).where.missing(:body_file_attachment).count
    puts "Found #{total} email logs with body content to migrate"

    migrated = 0
    failed = 0

    EmailLog.where.not(body: nil).where.missing(:body_file_attachment).find_each do |email_log|
      begin
        email_log.body_file.attach(
          io: StringIO.new(email_log.body),
          filename: "email_#{email_log.id}.html",
          content_type: "text/html"
        )
        migrated += 1
        print "." if migrated % 10 == 0
      rescue StandardError => e
        failed += 1
        puts "\nFailed to migrate email_log #{email_log.id}: #{e.message}"
      end
    end

    puts "\n\nMigration complete!"
    puts "  Migrated: #{migrated}"
    puts "  Failed: #{failed}"
    puts "\nNext steps:"
    puts "  1. Verify attachments are working: EmailLog.last.body_file.attached?"
    puts "  2. Run migration to remove body column: rails db:migrate"
  end

  desc "Clear legacy body column after verifying Active Storage migration"
  task clear_legacy_bodies: :environment do
    unless EmailLog.column_names.include?("body")
      puts "Body column no longer exists."
      exit 0
    end

    # Only clear bodies where Active Storage attachment exists
    count = EmailLog.where.not(body: nil).joins(:body_file_attachment).count
    puts "Found #{count} email logs with both legacy body and Active Storage attachment"

    print "Clear legacy body column for these records? (yes/no): "
    confirm = $stdin.gets.chomp.downcase

    if confirm == "yes"
      EmailLog.where.not(body: nil).joins(:body_file_attachment).update_all(body: nil)
      puts "Cleared #{count} legacy body values"
    else
      puts "Aborted"
    end
  end

  desc "Show email_logs storage statistics"
  task stats: :environment do
    puts "Email Log Statistics"
    puts "=" * 40

    total = EmailLog.count
    puts "Total email logs: #{total}"

    if EmailLog.column_names.include?("body")
      with_legacy_body = EmailLog.where.not(body: nil).count
      legacy_size = EmailLog.where.not(body: nil).sum("LENGTH(body)")
      puts "With legacy body column: #{with_legacy_body}"
      puts "Legacy body total size: #{ActiveSupport::NumberHelper.number_to_human_size(legacy_size)}"
    end

    with_attachment = EmailLog.joins(:body_file_attachment).count
    puts "With Active Storage attachment: #{with_attachment}"

    if with_attachment > 0
      attachment_size = ActiveStorage::Blob
        .joins(:attachments)
        .where(active_storage_attachments: { record_type: "EmailLog", name: "body_file" })
        .sum(:byte_size)
      puts "Active Storage total size: #{ActiveSupport::NumberHelper.number_to_human_size(attachment_size)}"
    end
  end
end
