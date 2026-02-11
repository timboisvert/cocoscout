# frozen_string_literal: true

# Script to unsubscribe senders from system-generated messages
#
# When system-generated messages were created, the sender (organization owner)
# was incorrectly subscribed to the thread. This script removes those subscriptions.
#
# Run in production console after deploy:
#   DRY_RUN=1 rails runner script/fix_system_generated_subscriptions.rb
#
# Once verified, run for real:
#   rails runner script/fix_system_generated_subscriptions.rb

DRY_RUN = ENV["DRY_RUN"].present?

puts "=" * 60
puts DRY_RUN ? "DRY RUN - No changes will be made" : "LIVE RUN - Subscriptions will be removed"
puts "=" * 60

# Find system-generated messages
system_messages = Message.where(system_generated: true)
puts "\nFound #{system_messages.count} system-generated messages"

# Find subscriptions where the sender is subscribed to their own system-generated message
subscriptions_to_remove = []

system_messages.find_each do |msg|
  sender = msg.sender
  next unless sender.is_a?(User)

  root_message = msg.root_message
  subscription = root_message.message_subscriptions.find_by(user: sender)

  if subscription
    # Check if sender is NOT also a recipient (they should stay subscribed if they're a recipient)
    is_recipient = root_message.message_recipients.where(recipient: sender.people).exists?

    unless is_recipient
      subscriptions_to_remove << {
        subscription: subscription,
        message_id: root_message.id,
        subject: root_message.subject,
        sender_email: sender.email_address
      }
    end
  end
end

puts "Found #{subscriptions_to_remove.count} sender subscriptions to remove"

if subscriptions_to_remove.any?
  puts "\nSample (first 10):"
  subscriptions_to_remove.first(10).each do |item|
    puts "  Message #{item[:message_id]}: '#{item[:subject]&.truncate(40)}' - unsubscribe #{item[:sender_email]}"
  end
end

if DRY_RUN
  puts "\n[DRY RUN] Would remove #{subscriptions_to_remove.count} subscriptions"
else
  puts "\nRemoving #{subscriptions_to_remove.count} subscriptions..."

  removed_count = 0
  subscriptions_to_remove.each do |item|
    item[:subscription].destroy
    removed_count += 1
    print "." if removed_count % 10 == 0
  end

  puts "\n\nDone! Removed #{removed_count} subscriptions."
end

puts "=" * 60
