# frozen_string_literal: true

namespace :email_logs do
  desc "Backfill production_id on existing email logs"
  task backfill_productions: :environment do
    puts "Starting email log production backfill..."

    # Mailer actions that are production-related
    production_mailer_actions = {
      "Manage::ShowMailer" => %w[canceled_notification],
      "Manage::ContactMailer" => %w[send_message],
      "VacancyInvitationMailer" => %w[invitation_email],
      "Manage::QuestionnaireMailer" => %w[invitation reminder],
      "AuditionMailer" => %w[invitation schedule_notification],
      "Manage::AuditionMailer" => %w[invitation schedule_notification]
    }

    updated_count = 0
    skipped_count = 0
    failed_count = 0

    EmailLog.where(production_id: nil).find_each do |email_log|
      production = nil

      # Method 1: Try to infer from subject line (e.g., "[Production Name] ...")
      if email_log.subject.present? && email_log.subject.start_with?("[")
        match = email_log.subject.match(/^\[([^\]]+)\]/)
        if match
          production_name = match[1]
          production = Production.find_by(name: production_name)
        end
      end

      # Method 2: If we have a recipient entity (Person), look at their talent pool memberships
      if production.nil? && email_log.recipient_entity.present?
        entity = email_log.recipient_entity
        if entity.is_a?(Person) && email_log.organization.present?
          # Get productions in this organization that the person is in the talent pool of
          productions = entity.talent_pool_productions
                              .where(organization: email_log.organization)
                              .order(created_at: :desc)

          # If there's only one, use it; otherwise take the most recent
          production = productions.first if productions.any?
        end
      end

      # Method 3: Check mailer class/action for production-related emails
      if production.nil? && email_log.mailer_class.present?
        mailer_class = email_log.mailer_class
        mailer_action = email_log.mailer_action

        if production_mailer_actions[mailer_class]&.include?(mailer_action)
          # This is a production-related email, try harder to find the production
          # Look at the most recent production for this organization
          if email_log.organization.present?
            production = email_log.organization.productions.order(created_at: :desc).first
          end
        end
      end

      if production.present?
        email_log.update_column(:production_id, production.id)
        updated_count += 1
        print "."
      else
        skipped_count += 1
      end
    rescue StandardError => e
      failed_count += 1
      puts "\nError processing email_log #{email_log.id}: #{e.message}"
    end

    puts "\n\nBackfill complete!"
    puts "Updated: #{updated_count}"
    puts "Skipped (no production found): #{skipped_count}"
    puts "Failed: #{failed_count}"
  end

  desc "Retroactively create email batches for emails sent together (same subject within 1 minute)"
  task backfill_batches: :environment do
    puts "Starting email batch backfill..."

    created_batches = 0
    updated_logs = 0

    # Find emails without batches, group by subject + approximate sent_at (within 1 minute)
    # We'll group by subject and sent_at truncated to the minute
    EmailLog.where(email_batch_id: nil)
            .where.not(subject: nil)
            .group(:subject, Arel.sql("DATE_TRUNC('minute', sent_at)"))
            .having("COUNT(*) > 1")
            .pluck(:subject, Arel.sql("DATE_TRUNC('minute', sent_at)"))
            .each do |subject, sent_minute|
      next if subject.blank? || sent_minute.blank?

      # Find all emails matching this subject sent within this minute
      logs = EmailLog.where(email_batch_id: nil)
                     .where(subject: subject)
                     .where("sent_at >= ? AND sent_at < ?", sent_minute, sent_minute + 1.minute)
                     .order(:id)

      next if logs.count <= 1

      # Get the user who sent these (from the first log, or nil)
      first_log = logs.first
      sender = first_log.user

      # Create a batch
      batch = EmailBatch.create!(
        user: sender,
        subject: subject,
        recipient_count: logs.count,
        sent_at: first_log.sent_at
      )

      # Update all logs to reference this batch
      logs.update_all(email_batch_id: batch.id)

      created_batches += 1
      updated_logs += logs.count
      print "."
    end

    puts "\n\nBatch backfill complete!"
    puts "Created batches: #{created_batches}"
    puts "Updated email logs: #{updated_logs}"
  end

  desc "Backfill recipient_entity on existing email logs by matching recipient email"
  task backfill_recipient_entities: :environment do
    puts "Starting email log recipient entity backfill..."

    updated_count = 0
    skipped_count = 0

    EmailLog.where(recipient_entity_id: nil)
            .where.not(recipient: nil)
            .find_each do |email_log|
      recipient_email = email_log.recipient&.downcase&.strip
      next if recipient_email.blank?

      # Try to find a Person with this email
      person = Person.find_by("LOWER(email) = ?", recipient_email)

      if person.present?
        email_log.update_columns(
          recipient_entity_type: "Person",
          recipient_entity_id: person.id
        )
        updated_count += 1
        print "."
      else
        # Try to find a Group with this email
        group = Group.find_by("LOWER(email) = ?", recipient_email)
        if group.present?
          email_log.update_columns(
            recipient_entity_type: "Group",
            recipient_entity_id: group.id
          )
          updated_count += 1
          print "."
        else
          skipped_count += 1
        end
      end
    end

    puts "\n\nRecipient entity backfill complete!"
    puts "Updated: #{updated_count}"
    puts "Skipped (no matching entity found): #{skipped_count}"
  end
end
