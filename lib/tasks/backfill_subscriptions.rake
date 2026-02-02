namespace :messages do
  desc "Backfill message subscriptions for existing messages"
  task backfill_subscriptions: :environment do
    puts "="*80
    puts "BACKFILLING MESSAGE SUBSCRIPTIONS"
    puts "="*80
    puts

    # Clear existing subscriptions first
    puts "Clearing existing subscriptions..."
    MessageSubscription.delete_all

    # Get all root messages (messages without a parent)
    root_messages = Message.where(parent_message_id: nil)
    puts "Found #{root_messages.count} root messages"

    created_count = 0

    # Group by message_batch_id to handle batches
    batches = root_messages.where.not(message_batch_id: nil)
                          .group_by(&:message_batch_id)

    single_messages = root_messages.where(message_batch_id: nil)

    # Handle batch messages - only subscribe to first message in each batch
    batches.each do |batch_id, messages|
      canonical_message = messages.first
      users_to_subscribe = []

      # Collect all users who should be subscribed
      messages.each do |message|
        # Add sender if User
        users_to_subscribe << message.sender if message.sender.is_a?(User)

        # Add recipient if they have a user account
        users_to_subscribe << message.recipient.user if message.recipient.is_a?(Person) && message.recipient.user

        # For production_contact, add managers
        if message.message_type == "production_contact" && message.sent_on_behalf_of.is_a?(Production)
          users_to_subscribe.concat(message.sent_on_behalf_of.managers)
        end
      end

      # Create subscriptions (one per user, to canonical message)
      users_to_subscribe.uniq.each do |user|
        canonical_message.subscribe!(user)
        created_count += 1
      end
    end

    # Handle single (non-batch) messages
    single_messages.find_each do |message|
      # Subscribe the sender if they're a User
      if message.sender.is_a?(User)
        message.subscribe!(message.sender)
        created_count += 1
      end

      # Subscribe the recipient if they have a user account
      if message.recipient.is_a?(Person) && message.recipient.user
        message.subscribe!(message.recipient.user)
        created_count += 1
      end

      # For production_contact messages, subscribe all managers
      if message.message_type == "production_contact" && message.sent_on_behalf_of.is_a?(Production)
        production = message.sent_on_behalf_of
        production.managers.each do |manager|
          message.subscribe!(manager)
          created_count += 1
        end
      end
    end

    puts
    puts "="*80
    puts "SUMMARY"
    puts "="*80
    puts "Subscriptions created: #{created_count}"
    puts
    puts "COMPLETE!"
    puts "="*80
  end
end
