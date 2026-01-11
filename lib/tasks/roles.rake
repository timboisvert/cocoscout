# frozen_string_literal: true

namespace :roles do
  desc "Merge numbered roles (e.g., 'Comic 1', 'Comic 2') into multi-person roles with quantity"
  task :merge_numbered, [ :dry_run ] => :environment do |_t, args|
    dry_run = args[:dry_run] != "false"

    puts dry_run ? "DRY RUN MODE - No changes will be made" : "ACTUAL RUN - Changes will be committed"
    puts "=" * 60

    productions = Production.all
    total_groups_merged = 0

    productions.each do |production|
      # Find production-level roles that match the pattern "Name N" where N is a number
      roles = production.roles.production_roles.to_a

      # Group roles by base name (strip trailing numbers and whitespace)
      grouped_roles = roles.group_by do |role|
        # Match patterns like "Comic 1", "Comic 2", "Host 1", etc.
        match = role.name.match(/^(.+?)\s+(\d+)$/)
        match ? match[1].strip : nil
      end

      # Filter to only groups with multiple roles (excluding nil key which means no number suffix)
      mergeable_groups = grouped_roles.reject { |k, v| k.nil? || v.size <= 1 }

      next if mergeable_groups.empty?

      puts "\nProduction: #{production.name} (ID: #{production.id})"
      puts "-" * 60
      puts "Found #{mergeable_groups.size} role group(s) to merge:"
      mergeable_groups.each do |base_name, group_roles|
        puts "  '#{base_name}' - #{group_roles.size} roles: #{group_roles.map(&:name).join(', ')}"
      end

      mergeable_groups.each do |base_name, group_roles|
        puts "\n=== Merging '#{base_name}' (#{group_roles.size} roles) ==="

        # Sort by the number suffix to maintain order
        sorted_roles = group_roles.sort_by do |role|
          match = role.name.match(/(\d+)$/)
          match ? match[1].to_i : 0
        end

        sorted_roles.each_with_index do |role, idx|
          puts "  #{idx + 1}. #{role.name} (ID: #{role.id})"
        end

        if dry_run
          puts "  [DRY RUN] Would create '#{base_name}' with quantity: #{sorted_roles.size}"
          puts "  [DRY RUN] Would reassign #{sorted_roles.sum { |r| r.show_person_role_assignments.count }} assignments"
          total_groups_merged += 1
          next
        end

        ActiveRecord::Base.transaction do
          # Create merged role with combined attributes
          first_role = sorted_roles.first
          merged_role = production.roles.create!(
            name: base_name,
            quantity: sorted_roles.size,
            category: first_role.category,
            position: sorted_roles.map(&:position).min,
            restricted: sorted_roles.any?(&:restricted?)
          )

          puts "  Created merged role: '#{merged_role.name}' (ID: #{merged_role.id}, quantity: #{merged_role.quantity})"

          # Merge eligibilities from all restricted source roles (union)
          if merged_role.restricted?
            eligibility_count = 0
            sorted_roles.each do |old_role|
              old_role.role_eligibilities.each do |eligibility|
                merged_role.role_eligibilities.find_or_create_by!(
                  member_type: eligibility.member_type,
                  member_id: eligibility.member_id
                )
                eligibility_count += 1
              end
            end
            puts "  Merged #{eligibility_count} eligibility records"
          end

          # Reassign existing assignments with sequential positions
          position = 1
          assignment_count = 0
          sorted_roles.each do |old_role|
            old_role.show_person_role_assignments.find_each do |assignment|
              assignment.update!(role: merged_role, position: position)
              position += 1
              assignment_count += 1
            end
          end
          puts "  Reassigned #{assignment_count} assignments with positions 1-#{position - 1}"

          # Update show_cast_notifications to reference new role
          notification_count = 0
          sorted_roles.each do |old_role|
            count = old_role.show_cast_notifications.update_all(role_id: merged_role.id)
            notification_count += count
          end
          puts "  Updated #{notification_count} cast notification records" if notification_count > 0

          # Update vacancies to reference new role
          vacancy_count = 0
          sorted_roles.each do |old_role|
            count = old_role.vacancies.update_all(role_id: merged_role.id)
            vacancy_count += count
          end
          puts "  Updated #{vacancy_count} vacancy records" if vacancy_count > 0

          # Delete old roles
          sorted_roles.each(&:destroy!)
          puts "  Deleted #{sorted_roles.size} old roles"

          puts "  [DONE] Successfully merged into '#{base_name}'"
          total_groups_merged += 1
        end
      end
    end

    puts "\n" + "=" * 60
    if total_groups_merged == 0
      puts "No numbered role groups found across any production."
      puts "Looking for patterns like 'Comic 1', 'Comic 2', 'Host 1', 'Host 2', etc."
    elsif dry_run
      puts "DRY RUN COMPLETE - Would merge #{total_groups_merged} role group(s)"
      puts "Run with 'false' arg to apply: rails 'roles:merge_numbered[false]'"
    else
      puts "MERGE COMPLETE - Merged #{total_groups_merged} role group(s)"
    end
  end

  desc "List roles that could be merged (numbered roles like 'Comic 1', 'Comic 2')"
  task list_mergeable: :environment do
    productions = Production.all
    found_any = false

    productions.each do |production|
      roles = production.roles.production_roles.to_a

      grouped_roles = roles.group_by do |role|
        match = role.name.match(/^(.+?)\s+(\d+)$/)
        match ? match[1].strip : nil
      end

      mergeable_groups = grouped_roles.reject { |k, v| k.nil? || v.size <= 1 }

      next if mergeable_groups.empty?

      found_any = true
      puts "\nProduction: #{production.name} (ID: #{production.id})"
      puts "-" * 60

      mergeable_groups.each do |base_name, group_roles|
        total_assignments = group_roles.sum { |r| r.show_person_role_assignments.count }
        puts "  '#{base_name}' => #{group_roles.size} roles, #{total_assignments} total assignments"
        group_roles.sort_by { |r| r.name.match(/(\d+)$/)[1].to_i }.each do |role|
          puts "    - #{role.name} (#{role.show_person_role_assignments.count} assignments)"
        end
      end
    end

    puts "\nNo numbered role groups found." unless found_any
  end
end
