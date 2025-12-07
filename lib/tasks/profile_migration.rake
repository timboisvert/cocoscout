# frozen_string_literal: true

namespace :profile do
  desc "Migrate legacy headshots and resumes to ProfileHeadshot and ProfileResume records"
  task migrate_files: :environment do
    puts "Starting migration of legacy headshots and resumes..."

    migrated_headshots = 0
    migrated_resumes = 0
    skipped_headshots = 0
    skipped_resumes = 0
    errors = []

    Person.find_each do |person|
      # Access the legacy headshot attachment directly via ActiveStorage
      legacy_headshot_attachment = ActiveStorage::Attachment.find_by(
        record_type: "Person",
        record_id: person.id,
        name: "headshot"
      )
      legacy_resume_attachment = ActiveStorage::Attachment.find_by(
        record_type: "Person",
        record_id: person.id,
        name: "resume"
      )

      # Migrate headshot if attached and not already migrated
      if legacy_headshot_attachment&.blob
        # Check if person already has a profile_headshot with this image
        existing = person.profile_headshots.any? do |ph|
          ph.image.attached? && ph.image.blob.key == legacy_headshot_attachment.blob.key
        end

        if existing
          skipped_headshots += 1
          puts "- Skipped headshot for #{person.name} (already migrated)"
        else
          profile_headshot = person.profile_headshots.build(
            is_primary: true,
            position: 0
          )

          # Attach the same blob to avoid re-uploading
          profile_headshot.image.attach(legacy_headshot_attachment.blob)

          if profile_headshot.save
            migrated_headshots += 1
            puts "✓ Migrated headshot for #{person.name} (ID: #{person.id})"
          else
            errors << "Failed to save profile_headshot for #{person.name}: #{profile_headshot.errors.full_messages.join(', ')}"
          end
        end
      end

      # Migrate resume if attached and not already migrated
      if legacy_resume_attachment&.blob
        existing = person.profile_resumes.any? do |pr|
          pr.file.attached? && pr.file.blob.key == legacy_resume_attachment.blob.key
        end

        if existing
          skipped_resumes += 1
          puts "- Skipped resume for #{person.name} (already migrated)"
        else
          profile_resume = person.profile_resumes.build(
            name: "Performance Resume",
            is_primary: true,
            position: 0
          )

          # Attach the same blob to avoid re-uploading
          profile_resume.file.attach(legacy_resume_attachment.blob)

          if profile_resume.save
            migrated_resumes += 1
            puts "✓ Migrated resume for #{person.name} (ID: #{person.id})"
          else
            errors << "Failed to save profile_resume for #{person.name}: #{profile_resume.errors.full_messages.join(', ')}"
          end
        end
      end
    rescue StandardError => e
      errors << "Error processing #{person.name} (ID: #{person.id}): #{e.message}"
    end

    puts "\n#{'=' * 80}"
    puts "Migration Summary:"
    puts "=" * 80
    puts "Headshots migrated: #{migrated_headshots}"
    puts "Headshots skipped (already migrated): #{skipped_headshots}"
    puts "Resumes migrated: #{migrated_resumes}"
    puts "Resumes skipped (already migrated): #{skipped_resumes}"
    puts "Errors: #{errors.count}"

    if errors.any?
      puts "\nErrors encountered:"
      errors.each { |error| puts "  - #{error}" }
    end

    puts "\nMigration complete!"
  end

  desc "Remove legacy headshots after confirming ProfileHeadshot migration"
  task clean_legacy_headshots: :environment do
    puts "WARNING: This will remove legacy person.headshot attachments"
    puts "Make sure you've run 'rake profile:migrate_files' first!"
    puts ""
    print "Are you sure you want to continue? (yes/no): "

    confirmation = $stdin.gets.chomp

    if confirmation.downcase == "yes"
      removed_count = 0

      Person.find_each do |person|
        legacy_headshot_attachment = ActiveStorage::Attachment.find_by(
          record_type: "Person",
          record_id: person.id,
          name: "headshot"
        )
        if legacy_headshot_attachment&.blob && person.profile_headshots.any? { |ph| ph.image.attached? }
          legacy_headshot_attachment.purge
          removed_count += 1
          puts "✓ Removed legacy headshot for #{person.name} (ID: #{person.id})"
        end
      end

      puts "\nRemoved #{removed_count} legacy headshot attachments"
    else
      puts "Cancelled."
    end
  end

  desc "Clean up ProfileHeadshot and ProfileResume records without attached files"
  task clean_broken_records: :environment do
    puts "Cleaning up ProfileHeadshot and ProfileResume records without attached files..."

    broken_headshots = 0
    broken_resumes = 0

    ProfileHeadshot.find_each do |ph|
      unless ph.image.attached?
        ph.destroy
        broken_headshots += 1
        puts "✓ Removed ProfileHeadshot #{ph.id} (no image attached)"
      end
    end

    ProfileResume.find_each do |pr|
      unless pr.file.attached?
        pr.destroy
        broken_resumes += 1
        puts "✓ Removed ProfileResume #{pr.id} (no file attached)"
      end
    end

    puts "\nCleaned up #{broken_headshots} ProfileHeadshot records"
    puts "Cleaned up #{broken_resumes} ProfileResume records"
  end
end
