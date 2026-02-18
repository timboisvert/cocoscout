class MessageService
  class << self
    # Send to cast of a specific show
    # Recipients are People assigned to the show
    # visibility: :show (team + show cast), :production (all team), or :personal (private)
    def send_to_show_cast(show:, sender:, subject:, body:, visibility: :show)
      # Get People (not Users) who are cast in this show
      people = show.show_person_role_assignments.includes(:assignable).map do |assignment|
        assignment.assignable.is_a?(Person) ? assignment.assignable : assignment.assignable.members
      end.flatten.uniq

      create_message(
        sender: sender,
        recipients: people,
        subject: subject,
        body: body,
        organization: show.production.organization,
        production: show.production,
        show: show,
        visibility: visibility,
        message_type: :cast_contact
      )
    end

    # Send to all cast of a production (all shows)
    def send_to_production_cast(production:, sender:, subject:, body:)
      people = production.cast_people.to_a

      create_message(
        sender: sender,
        recipients: people,
        subject: subject,
        body: body,
        organization: production.organization,
        production: production,
        visibility: :production,
        message_type: :cast_contact
      )
    end

    # Send to talent pool members
    # visibility: :production (all team) or :personal (private)
    def send_to_talent_pool(production:, sender:, subject:, body:, person_ids: nil, visibility: :production)
      pool = production.effective_talent_pool
      people = person_ids ? pool.people.where(id: person_ids).to_a : pool.people.to_a

      create_message(
        sender: sender,
        recipients: people,
        subject: subject,
        body: body,
        organization: production.organization,
        production: production,
        visibility: visibility,
        message_type: :talent_pool
      )
    end

    # Send to production team (cast → managers)
    def send_to_production_team(production:, sender:, subject:, body:, parent_message: nil)
      # Get org-level managers/viewers for this production's organization
      org_manager_user_ids = production.organization
        .organization_roles
        .where(company_role: [ :manager, :viewer ])
        .pluck(:user_id)

      # Get production-level managers/viewers
      production_manager_user_ids = production
        .production_permissions
        .where(role: [ :manager, :viewer ])
        .pluck(:user_id)

      # Combine and get unique user IDs
      manager_user_ids = (org_manager_user_ids + production_manager_user_ids).uniq

      # Get people for these users (use default_person association)
      people = User.where(id: manager_user_ids).includes(:default_person).map(&:person).compact

      create_message(
        sender: sender,
        recipients: people,
        subject: subject,
        body: body,
        organization: production.organization,
        production: production,
        visibility: :personal,  # Personal = only sender + explicit recipients
        message_type: :production_contact,
        parent_message: parent_message
      )
    end

    # Send direct message to a specific Person (private)
    # system_generated: true for automated/transactional messages that shouldn't appear in sender's sent folder
    def send_direct(sender:, recipient_person:, subject:, body:, organization: nil, parent_message: nil, production: nil, system_generated: false)
      create_message(
        sender: sender,
        recipients: [ recipient_person ],
        subject: subject,
        body: body,
        organization: organization,
        production: production,
        visibility: :personal,
        message_type: :direct,
        parent_message: parent_message,
        system_generated: system_generated
      )
    end

    # Send to a Group (all members receive, show-scoped)
    def send_to_group(sender:, group:, subject:, body:, show: nil, production: nil, parent_message: nil)
      prod = production || group.production || show&.production

      create_message(
        sender: sender,
        recipients: group.members.to_a,
        subject: subject,
        body: body,
        organization: prod&.organization,
        production: prod,
        show: show,
        visibility: show ? :show : :production,
        message_type: :cast_contact,
        parent_message: parent_message
      )
    end

    # Send to multiple people at once (batch direct messages)
    # Creates a single message visible to the sender with all recipients
    # visibility: :personal (private) or :production (all team)
    def send_to_people(sender:, people:, subject:, body:, message_type: :direct, organization: nil, production: nil, visibility: :personal)
      create_message(
        sender: sender,
        recipients: Array(people),
        subject: subject,
        body: body,
        organization: organization,
        production: production,
        visibility: visibility,
        message_type: message_type
      )
    end

    # Core method: create a single message with multiple recipients
    # system_generated: true for automated/transactional messages (sign-up confirmations, etc.)
    def create_message(sender:, recipients:, subject:, body:, message_type:,
                       organization: nil, production: nil, show: nil,
                       visibility: nil, parent_message: nil, system_generated: false)
      # Filter to people with accounts
      recipients = Array(recipients).uniq.select { |p| p.is_a?(Person) && p.user.present? }
      return nil if recipients.empty?

      # If replying, inherit context from parent (only inherit visibility if not explicitly passed)
      if parent_message
        production ||= parent_message.production
        show ||= parent_message.show
        organization ||= parent_message.organization
        visibility ||= parent_message.visibility
      end

      # Default visibility if still not set
      visibility ||= :personal

      # Create the message (skip automatic notification - we'll call it after subscriptions exist)
      message = Message.new(
        sender: sender,
        organization: organization,
        production: production,
        show: show,
        visibility: visibility,
        subject: subject,
        body: body,
        message_type: message_type,
        parent_message: parent_message,
        system_generated: system_generated
      )
      message.skip_notify_subscribers = true
      message.save!

      # Create recipient records
      recipients.each do |person|
        message.message_recipients.create!(recipient: person)
      end

      # Get root message for subscriptions
      root_message = message.root_message

      # Subscribe sender and mark as read (sender shouldn't see their own message as unread)
      # But NOT for system-generated messages - the sender shouldn't see automated notifications
      if sender.is_a?(User) && !system_generated
        root_message.subscribe!(sender, mark_read: true)
      end

      # Subscribe all recipients
      recipients.each do |person|
        root_message.subscribe!(person.user)
      end

      # For production/show visibility, subscribe the entire production team
      if visibility.to_sym.in?([ :production, :show ]) && production
        root_message.subscribe_production_team!
      end

      # Now notify all subscribers (increment unread counts) since subscriptions exist
      message.send(:notify_subscribers)

      # Note: Email notifications are now handled by UnreadDigestJob
      # which sends a digest after 1 hour if user hasn't checked their inbox

      # Broadcast to ActionCable if this is a reply
      if parent_message.present?
        broadcast_new_reply(message)
      end

      # Broadcast inbox notification to all subscribers (except sender)
      broadcast_inbox_notification(message)

      message
    end

    # Reply to a message thread
    # If visibility is explicitly passed, use that; otherwise inherit from root message
    def reply(sender:, parent_message:, body:, visibility: nil)
      root = parent_message.root_message

      # Determine visibility: use explicit override or inherit from root
      reply_visibility = visibility || root.visibility

      # For direct messages, recipient is the other party
      # For production messages, no explicit recipient needed (visibility handles it)
      if reply_visibility == "personal"
        # Find the other party in the conversation
        # This could be the original sender OR one of the original recipients
        sender_person = sender.is_a?(User) ? sender.person : sender

        # Get original sender's person record
        original_sender_person = root.sender.is_a?(User) ? root.sender.person : root.sender

        # Get original recipients
        original_recipients = root.message_recipients.map(&:recipient)

        # If the replier is the original sender, reply to original recipients
        # If the replier is one of the original recipients, reply to original sender
        if sender_person == original_sender_person
          # Sender is replying - send to original recipients (excluding themselves if they were included)
          recipients = original_recipients.reject { |r| r == sender_person }
        else
          # Recipient is replying - send to original sender
          recipients = original_sender_person ? [ original_sender_person ] : []
        end
      else
        # For production/show messages, reply goes to original sender
        original_sender_person = root.sender.is_a?(Person) ? root.sender : root.sender.person
        recipients = original_sender_person ? [ original_sender_person ] : []
      end

      create_message(
        sender: sender,
        recipients: recipients,
        subject: "Re: #{root.subject}",
        body: body,
        message_type: root.message_type,
        parent_message: parent_message,
        production: root.production,
        show: root.show,
        visibility: reply_visibility,
        organization: root.organization
      )
    end

    private

    def broadcast_new_reply(message)
      root = message.root_message
      parent = message.parent_message

      Rails.logger.info "[MessageService] Broadcasting new reply: message_id=#{message.id}, parent_id=#{parent.id}, root_id=#{root.id}, depth=#{message.thread_depth}"

      # Get default URL options for rendering (needed for image URLs)
      url_options = Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
      host = url_options[:host]
      port = url_options[:port]
      protocol = url_options[:protocol] || "http"

      # Build the full host string for URL generation
      full_host = port ? "#{host}:#{port}" : host

      # Render the reply HTML with proper URL options
      html = ApplicationController.renderer.new(
        http_host: full_host,
        https: protocol == "https"
      ).render(
        partial: "shared/messages/nested_reply",
        locals: {
          reply: message,
          depth: message.thread_depth,
          is_last: true,
          broadcast_host: full_host,
          broadcast_protocol: protocol
        }
      )

      # For the parent_id, we want the direct parent's ID so JS can find where to insert
      broadcast_parent_id = parent.id

      # Broadcast to the root message channel
      begin
        MessageThreadChannel.broadcast_to(root, {
          type: "new_reply",
          message_id: message.id,
          parent_id: broadcast_parent_id,
          root_id: root.id,
          sender_id: message.sender_id,
          sender_name: message.sender_name,
          depth: message.thread_depth,
          html: html
        })
      rescue ArgumentError => e
        # Solid Cable can have issues with unique index lookups in Rails 8.1
        Rails.logger.warn "ActionCable broadcast failed: #{e.message}"
      end
    end

    # Broadcast to all subscribers' inboxes that a new message arrived
    def broadcast_inbox_notification(message)
      root = message.root_message
      sender_user_id = message.sender_id if message.sender_type == "User"

      # Get all subscribed users except the sender
      root.message_subscriptions.includes(:user).find_each do |subscription|
        next unless subscription.user
        next if subscription.user.id == sender_user_id # Don't notify sender

        begin
          UserInboxChannel.broadcast_new_message(subscription.user, message)
        rescue ArgumentError => e
          # Solid Cable can have issues with unique index lookups in Rails 8.1
          # Log but don't fail message creation
          Rails.logger.warn "ActionCable broadcast failed: #{e.message}"
        end
      end
    end
  end
end
