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

    person_emails = Person.where.not(email: [nil, ""]).pluck(:email, :id).to_h
    puts "  - #{person_emails.size} people with emails"

    group_emails = Group.where.not(email: [nil, ""]).pluck(:email, :id).to_h
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
end
