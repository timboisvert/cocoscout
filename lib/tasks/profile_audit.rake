namespace :profile do
  desc "Audit legacy headshot and resume usage vs new profile system"
  task audit: :environment do
    puts "=" * 80
    puts "PROFILE SYSTEM AUDIT"
    puts "=" * 80
    puts ""

    # People audit
    puts "PEOPLE AUDIT"
    puts "-" * 80

    total_people = Person.count
    people_with_legacy_headshot = 0
    people_with_profile_headshot = 0
    people_with_legacy_resume = 0
    people_with_profile_resume = 0
    people_with_both_headshot = 0
    people_with_both_resume = 0
    people_with_only_legacy_headshot = 0
    people_with_only_legacy_resume = 0

    Person.find_each do |person|
      # Check headshots
      has_legacy_headshot = ActiveStorage::Attachment.exists?(
        record_type: "Person",
        record_id: person.id,
        name: "headshot"
      )
      has_profile_headshot = person.profile_headshots.any?

      if has_legacy_headshot
        people_with_legacy_headshot += 1
      end

      if has_profile_headshot
        people_with_profile_headshot += 1
      end

      if has_legacy_headshot && has_profile_headshot
        people_with_both_headshot += 1
      elsif has_legacy_headshot && !has_profile_headshot
        people_with_only_legacy_headshot += 1
      end

      # Check resumes
      has_legacy_resume = ActiveStorage::Attachment.exists?(
        record_type: "Person",
        record_id: person.id,
        name: "resume"
      )
      has_profile_resume = person.profile_resumes.any?

      if has_legacy_resume
        people_with_legacy_resume += 1
      end

      if has_profile_resume
        people_with_profile_resume += 1
      end

      if has_legacy_resume && has_profile_resume
        people_with_both_resume += 1
      elsif has_legacy_resume && !has_profile_resume
        people_with_only_legacy_resume += 1
      end
    end

    puts "Total People: #{total_people}"
    puts ""
    puts "Headshots:"
    puts "  People with legacy headshot: #{people_with_legacy_headshot}"
    puts "  People with profile headshot: #{people_with_profile_headshot}"
    puts "  People with BOTH headshots: #{people_with_both_headshot}"
    puts "  People with ONLY legacy headshot: #{people_with_only_legacy_headshot}"
    puts ""
    puts "Resumes:"
    puts "  People with legacy resume: #{people_with_legacy_resume}"
    puts "  People with profile resume: #{people_with_profile_resume}"
    puts "  People with BOTH resumes: #{people_with_both_resume}"
    puts "  People with ONLY legacy resume: #{people_with_only_legacy_resume}"
    puts ""

    # Groups audit
    puts "GROUPS AUDIT"
    puts "-" * 80

    total_groups = Group.count
    groups_with_legacy_headshot = 0
    groups_with_profile_headshot = 0
    groups_with_legacy_resume = 0
    groups_with_profile_resume = 0
    groups_with_both_headshot = 0
    groups_with_both_resume = 0
    groups_with_only_legacy_headshot = 0
    groups_with_only_legacy_resume = 0

    Group.find_each do |group|
      # Check headshots
      has_legacy_headshot = ActiveStorage::Attachment.exists?(
        record_type: "Group",
        record_id: group.id,
        name: "headshot"
      )
      has_profile_headshot = group.profile_headshots.any?

      if has_legacy_headshot
        groups_with_legacy_headshot += 1
      end

      if has_profile_headshot
        groups_with_profile_headshot += 1
      end

      if has_legacy_headshot && has_profile_headshot
        groups_with_both_headshot += 1
      elsif has_legacy_headshot && !has_profile_headshot
        groups_with_only_legacy_headshot += 1
      end

      # Check resumes
      has_legacy_resume = ActiveStorage::Attachment.exists?(
        record_type: "Group",
        record_id: group.id,
        name: "resume"
      )
      has_profile_resume = group.profile_resumes.any?

      if has_legacy_resume
        groups_with_legacy_resume += 1
      end

      if has_profile_resume
        groups_with_profile_resume += 1
      end

      if has_legacy_resume && has_profile_resume
        groups_with_both_resume += 1
      elsif has_legacy_resume && !has_profile_resume
        groups_with_only_legacy_resume += 1
      end
    end

    puts "Total Groups: #{total_groups}"
    puts ""
    puts "Headshots:"
    puts "  Groups with legacy headshot: #{groups_with_legacy_headshot}"
    puts "  Groups with profile headshot: #{groups_with_profile_headshot}"
    puts "  Groups with BOTH headshots: #{groups_with_both_headshot}"
    puts "  Groups with ONLY legacy headshot: #{groups_with_only_legacy_headshot}"
    puts ""
    puts "Resumes:"
    puts "  Groups with legacy resume: #{groups_with_legacy_resume}"
    puts "  Groups with profile resume: #{groups_with_profile_resume}"
    puts "  Groups with BOTH resumes: #{groups_with_both_resume}"
    puts "  Groups with ONLY legacy resume: #{groups_with_only_legacy_resume}"
    puts ""

    # Summary
    puts "=" * 80
    puts "MIGRATION STATUS SUMMARY"
    puts "=" * 80

    total_only_legacy = people_with_only_legacy_headshot + people_with_only_legacy_resume +
                        groups_with_only_legacy_headshot + groups_with_only_legacy_resume

    if total_only_legacy == 0
      puts "✅ All legacy attachments have been migrated to profile system!"
      puts "   Safe to remove legacy headshot/resume code."
    else
      puts "⚠️  WARNING: #{total_only_legacy} legacy attachments still in use:"
      if people_with_only_legacy_headshot > 0
        puts "   - #{people_with_only_legacy_headshot} people with ONLY legacy headshot"
      end
      if people_with_only_legacy_resume > 0
        puts "   - #{people_with_only_legacy_resume} people with ONLY legacy resume"
      end
      if groups_with_only_legacy_headshot > 0
        puts "   - #{groups_with_only_legacy_headshot} groups with ONLY legacy headshot"
      end
      if groups_with_only_legacy_resume > 0
        puts "   - #{groups_with_only_legacy_resume} groups with ONLY legacy resume"
      end
      puts ""
      puts "   Run 'rails profile:migrate_files' to migrate remaining files."
      puts "   DO NOT remove legacy code until this shows 0 legacy-only attachments."
    end
    puts ""

    # Show detailed list if there are only a few remaining
    if total_only_legacy > 0 && total_only_legacy <= 20
      puts "=" * 80
      puts "DETAILED LIST OF LEGACY-ONLY ATTACHMENTS"
      puts "=" * 80

      Person.find_each do |person|
        has_legacy_headshot = ActiveStorage::Attachment.exists?(
          record_type: "Person",
          record_id: person.id,
          name: "headshot"
        )
        has_profile_headshot = person.profile_headshots.any?
        has_legacy_resume = ActiveStorage::Attachment.exists?(
          record_type: "Person",
          record_id: person.id,
          name: "resume"
        )
        has_profile_resume = person.profile_resumes.any?

        if (has_legacy_headshot && !has_profile_headshot) || (has_legacy_resume && !has_profile_resume)
          issues = []
          issues << "headshot" if has_legacy_headshot && !has_profile_headshot
          issues << "resume" if has_legacy_resume && !has_profile_resume
          puts "Person ##{person.id} (#{person.name}): legacy #{issues.join(', ')}"
        end
      end

      Group.find_each do |group|
        has_legacy_headshot = ActiveStorage::Attachment.exists?(
          record_type: "Group",
          record_id: group.id,
          name: "headshot"
        )
        has_profile_headshot = group.profile_headshots.any?
        has_legacy_resume = ActiveStorage::Attachment.exists?(
          record_type: "Group",
          record_id: group.id,
          name: "resume"
        )
        has_profile_resume = group.profile_resumes.any?

        if (has_legacy_headshot && !has_profile_headshot) || (has_legacy_resume && !has_profile_resume)
          issues = []
          issues << "headshot" if has_legacy_headshot && !has_profile_headshot
          issues << "resume" if has_legacy_resume && !has_profile_resume
          puts "Group ##{group.id} (#{group.name}): legacy #{issues.join(', ')}"
        end
      end
      puts ""
    end

    puts "=" * 80
  end
end
