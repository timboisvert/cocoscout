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
      begin
        # Migrate headshot if attached and not already migrated
        if person.headshot.attached?
          # Check if person already has a profile_headshot with this image
          existing = person.profile_headshots.any? do |ph|
            ph.image.attached? && ph.image.blob.key == person.headshot.blob.key
          end

          unless existing
            profile_headshot = person.profile_headshots.build(
              category: "theatrical",
              is_primary: true,
              position: 0
            )

            # Attach the same blob to avoid re-uploading
            profile_headshot.image.attach(person.headshot.blob)

            if profile_headshot.save
              migrated_headshots += 1
              puts "✓ Migrated headshot for #{person.name} (ID: #{person.id})"
            else
              errors << "Failed to save profile_headshot for #{person.name}: #{profile_headshot.errors.full_messages.join(', ')}"
            end
          else
            skipped_headshots += 1
            puts "- Skipped headshot for #{person.name} (already migrated)"
          end
        end

        # Migrate resume if attached and not already migrated
        if person.resume.attached?
          existing = person.profile_resumes.any? do |pr|
            pr.file.attached? && pr.file.blob.key == person.resume.blob.key
          end

          unless existing
            profile_resume = person.profile_resumes.build(
              name: "Performance Resume",
              is_primary: true,
              position: 0
            )

            # Attach the same blob to avoid re-uploading
            profile_resume.file.attach(person.resume.blob)

            if profile_resume.save
              migrated_resumes += 1
              puts "✓ Migrated resume for #{person.name} (ID: #{person.id})"
            else
              errors << "Failed to save profile_resume for #{person.name}: #{profile_resume.errors.full_messages.join(', ')}"
            end
          else
            skipped_resumes += 1
            puts "- Skipped resume for #{person.name} (already migrated)"
          end
        end

      rescue => e
        errors << "Error processing #{person.name} (ID: #{person.id}): #{e.message}"
      end
    end

    puts "\n" + "="*80
    puts "Migration Summary:"
    puts "="*80
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

    confirmation = STDIN.gets.chomp

    if confirmation.downcase == "yes"
      removed_count = 0

      Person.find_each do |person|
        if person.headshot.attached? && person.profile_headshots.any?
          person.headshot.purge
          removed_count += 1
          puts "✓ Removed legacy headshot for #{person.name} (ID: #{person.id})"
        end
      end

      puts "\nRemoved #{removed_count} legacy headshot attachments"
    else
      puts "Cancelled."
    end
  end
end
