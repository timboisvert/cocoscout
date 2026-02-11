# frozen_string_literal: true

# Script to retroactively mark system-generated messages
#
# Run in production console after deploy:
#   rails runner script/backfill_system_generated_messages.rb
#
# Or for a dry run:
#   DRY_RUN=1 rails runner script/backfill_system_generated_messages.rb

DRY_RUN = ENV["DRY_RUN"].present?

puts "=" * 60
puts DRY_RUN ? "DRY RUN - No changes will be made" : "LIVE RUN - Messages will be updated"
puts "=" * 60

# Template subject patterns that indicate system-generated messages
# These are messages sent TO talent (not TO producers)
SYSTEM_MESSAGE_SUBJECT_PATTERNS = [
  # Sign-up notifications (to talent)
  /^You're signed up for /i,
  /^You're on the waitlist for /i,
  /^You've been assigned /i,
  /^Your slot has changed/i,
  /^Sign-up cancelled/i,

  # Vacancy notifications (to talent)
  /^Role Available:/i,
  /^You've been cast/i,

  # Casting notifications (to talent)
  /^You've been added to/i,
  /^Role assignment update/i,
  /^You've been removed from/i,
  /^Cast Finalized:/i,

  # Audition notifications (to talent)
  /^Audition Request Received/i,
  /^Audition Request Update/i,
  /^You're invited to audition/i,

  # Show notifications (to talent)
  /^Show Update:/i,
  /^Show Canceled:/i,
  /^Show Cancelled:/i,
  /^Show Reminder:/i
].freeze

# Count current state
total_messages = Message.count
already_system = Message.where(system_generated: true).count
puts "\nCurrent state:"
puts "  Total messages: #{total_messages}"
puts "  Already marked system_generated: #{already_system}"

# Find messages matching our patterns
matching_messages = Message.where(system_generated: false).select do |msg|
  SYSTEM_MESSAGE_SUBJECT_PATTERNS.any? { |pattern| msg.subject&.match?(pattern) }
end

puts "\nFound #{matching_messages.count} messages matching system-generated patterns"

# Group by subject for review
subject_counts = matching_messages.group_by(&:subject).transform_values(&:count)
puts "\nMatching subjects:"
subject_counts.sort_by { |_, count| -count }.first(20).each do |subject, count|
  puts "  #{count.to_s.rjust(4)}x  #{subject&.truncate(60)}"
end

if DRY_RUN
  puts "\n[DRY RUN] Would update #{matching_messages.count} messages"
else
  puts "\nUpdating #{matching_messages.count} messages..."

  updated_count = 0
  matching_messages.each do |msg|
    msg.update_column(:system_generated, true)
    updated_count += 1
    print "." if updated_count % 10 == 0
  end

  puts "\n\nDone! Updated #{updated_count} messages."
end

puts "\n" + "=" * 60
puts "Final state:"
puts "  Total messages: #{Message.count}"
puts "  System-generated: #{Message.where(system_generated: true).count}"
puts "  Regular messages: #{Message.where(system_generated: false).count}"
puts "=" * 60
