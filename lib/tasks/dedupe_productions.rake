# frozen_string_literal: true

namespace :productions do
  desc "Merge duplicate productions (contract/course bugs) onto one winner each. Dry-run unless EXECUTE=1."
  task dedupe_duplicates: :environment do
    execute = ENV["EXECUTE"] == "1"

    groups = DuplicateProductionMerger.duplicate_groups
    if groups.empty?
      puts "✅ No duplicate production groups found."
      next
    end

    puts "Found #{groups.size} duplicate group(s)."
    puts(execute ? "EXECUTING — data will be changed." : "DRY RUN — set EXECUTE=1 to apply.")

    groups.each_with_index do |prods, index|
      puts "\n=== Group #{index + 1}: #{prods.map { |p| "##{p.id} #{p.name.inspect} (#{p.production_type})" }.join(', ')} ==="
      result = DuplicateProductionMerger.new(prods).call(dry_run: !execute)
      result.actions.each { |action| puts action }
    end

    puts "\n#{execute ? '✅ Applied.' : 'ℹ️  Nothing changed (dry run). Re-run with EXECUTE=1 to apply.'}"
  end
end
