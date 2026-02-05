module Manage
  class MessagesController < Manage::ManageController
    rescue_from ActiveRecord::RecordNotFound, with: :message_not_found

    def index
      # Filter params
      @filter = params[:filter] || "all"
      @search = params[:q].to_s.strip
      @production_filter = params[:production_id]
      @order = params[:order] || "newest"

      # Get all productions the user has access to
      @accessible_productions = Current.user.accessible_productions
        .where(organization: Current.organization)
        .order(:name)
      accessible_production_ids = @accessible_productions.pluck(:id)

      person_ids = Current.user.people.pluck(:id)

      # Managers see:
      # 1. All production/show-scoped messages for accessible productions
      # 2. Private messages where they're sender or recipient (their personal DMs)
      private_received_ids = Message.joins(:message_recipients)
                                    .where(message_recipients: { recipient_type: "Person", recipient_id: person_ids })
                                    .select(:id)

      @messages = Message
        .where(organization: Current.organization)
        .root_messages
        .where(
          "(messages.visibility IN (?) AND messages.production_id IN (?)) OR " +
          "(messages.visibility = ? AND messages.sender_type = ? AND messages.sender_id = ?) OR " +
          "(messages.visibility = ? AND messages.id IN (?))",
          [ "production", "show" ], accessible_production_ids,
          "private", "User", Current.user.id,
          "private", private_received_ids
        )
        .includes(:sender, :message_recipients, :child_messages, :production, :show, images_attachments: :blob)

      # Apply filters
      case @filter
      when "unread"
        unread_thread_ids = Current.user.message_subscriptions.unread.pluck(:message_id)
        @messages = @messages.where(id: unread_thread_ids)
      when "sent_by_me"
        @messages = @messages.where(sender: Current.user)
      end

      # Filter by production
      if @production_filter.present?
        @messages = @messages.where(production_id: @production_filter)
      end

      # Search filter (body is in action_text_rich_texts table)
      if @search.present?
        @messages = @messages
          .left_joins(:rich_text_body)
          .where("messages.subject ILIKE :q OR action_text_rich_texts.body ILIKE :q", q: "%#{@search}%")
      end

      # Apply ordering
      @messages = @order == "oldest" ? @messages.order(updated_at: :asc) : @messages.order(updated_at: :desc)
      @messages = @messages.limit(100)
      @unread_count = Current.user.unread_message_count
    end

    # GET /manage/messages/production/:production_id
    def production
      @production = Current.user.accessible_productions
                                .where(organization: Current.organization)
                                .find(params[:production_id])

      # Get all messages for this production (production + show scoped, plus private messages)
      person_ids = Current.user.people.pluck(:id)
      private_received_ids = Message.joins(:message_recipients)
                                    .where(message_recipients: { recipient_type: "Person", recipient_id: person_ids })
                                    .select(:id)

      @messages = Message
        .where(production: @production)
        .root_messages
        .where(
          "visibility IN (?) OR " +
          "(visibility = ? AND sender_type = ? AND sender_id = ?) OR " +
          "(visibility = ? AND id IN (?))",
          [ "production", "show" ],
          "private", "User", Current.user.id,
          "private", private_received_ids
        )
        .includes(:sender, :message_recipients, :child_messages, :show, images_attachments: :blob)
        .order(updated_at: :desc)
        .limit(100)

      @hide_production_via = true  # Don't show "via" since we're already filtered by production
      render :production
    end

    def show
      @message = Message.find(params[:id])
      @root_message = @message.root_message

      # Mark as read for user's person if they're a recipient
      if Current.user.person
        @root_message.mark_read_for!(Current.user.person)
      end

      # Mark subscription as read
      subscription = @root_message.message_subscriptions.find_by(user: Current.user)
      subscription&.mark_read!

      # Load all messages in thread
      @thread_messages = Message.where(id: [ @root_message.id ] + @root_message.descendant_ids)
                                .includes(:sender, :message_recipients)
                                .order(:created_at)
    end

    # POST /manage/messages
    # Unified endpoint for sending messages to people, groups, or shows
    def create
      subject = params[:subject]
      body = params[:body]
      recipient_type = params[:recipient_type]
      recipient_id = params[:recipient_id]
      images = params[:images]&.reject(&:blank?)

      if subject.blank? || body.blank?
        redirect_back fallback_location: manage_messages_path, alert: "Subject and message are required"
        return
      end

      case recipient_type
      when "person"
        person = Current.organization.people.find(recipient_id)
        message = MessageService.send_direct(
          sender: Current.user,
          recipient_person: person,
          subject: subject,
          body: body,
          organization: Current.organization
        )
        message&.images&.attach(images) if images.present?
        redirect_to manage_messages_path, notice: "Message sent to #{person.name}"

      when "group"
        group = Current.organization.groups.find(recipient_id)
        production = group.production || Current.production
        message = MessageService.send_to_group(
          sender: Current.user,
          group: group,
          subject: subject,
          body: body,
          production: production
        )
        message&.images&.attach(images) if images.present?
        redirect_to manage_messages_path, notice: "Message sent to #{group.name}"

      when "show_cast"
        show = Show.joins(:production).where(productions: { organization_id: Current.organization.id }).find(recipient_id)
        message = MessageService.send_to_show_cast(
          show: show,
          sender: Current.user,
          subject: subject,
          body: body
        )
        message&.images&.attach(images) if images.present?
        redirect_to manage_messages_path, notice: "Message sent to #{show.display_name} cast"

      when "batch"
        # Handle batch messaging from directory selection or agreement reminders
        person_ids = params[:person_ids]&.select(&:present?) || []
        send_separately = params[:send_separately] == "1" || params[:send_separately] == "on"

        if person_ids.empty?
          redirect_back fallback_location: manage_directory_path, alert: "Please select at least one person or group."
          return
        end

        # Load people and groups from the IDs (scoped to current organization)
        people = Current.organization.people.where(id: person_ids)
        groups = Current.organization.groups.where(id: person_ids)

        # Collect all people to message (direct people + group members with notifications enabled)
        people_to_message = people.to_a

        groups.each do |group|
          members_with_notifications = group.group_memberships.select(&:notifications_enabled?).map(&:person)
          people_to_message.concat(members_with_notifications)
        end

        people_to_message.uniq!

        if send_separately
          # Send individual messages to each person
          messages_sent = 0
          people_to_message.each do |person|
            message = MessageService.send_direct(
              sender: Current.user,
              recipient_person: person,
              subject: subject,
              body: body,
              organization: Current.organization
            )
            if message
              message.images.attach(images) if images.present?
              messages_sent += 1
            end
          end
          redirect_to manage_messages_path, notice: "Sent #{messages_sent} individual #{'message'.pluralize(messages_sent)}."
        else
          # Send as a single message to all recipients (default behavior)
          message = MessageService.send_to_people(
            sender: Current.user,
            people: people_to_message,
            subject: subject,
            body: body,
            message_type: :direct,
            organization: Current.organization
          )
          message&.images&.attach(images) if images.present?
          redirect_to manage_messages_path, notice: "Message sent to #{people_to_message.count} #{'recipient'.pluralize(people_to_message.count)}."
        end

      else
        redirect_back fallback_location: manage_messages_path, alert: "Invalid recipient type"
      end
    end

    # POST /manage/messages/:id/reply
    def reply
      parent_message_id = params[:parent_message_id] || params[:id]
      parent = Message.find(parent_message_id)
      root_message = parent.root_message
      images = params[:images]&.reject(&:blank?)

      # Ensure user has access (subscribed to thread)
      unless root_message.subscribed?(Current.user)
        redirect_to manage_messages_path, alert: "You don't have access to this thread"
        return
      end

      message = MessageService.reply(
        sender: Current.user,
        parent_message: parent,
        body: params[:body]
      )
      message&.images&.attach(images) if images.present?

      respond_to do |format|
        format.html { redirect_to manage_message_path(root_message), notice: "Reply sent" }
      end
    end

    # POST /manage/messages/:id/react/:emoji
    def react
      message = Message.find(params[:id])
      emoji = params[:emoji]

      # Validate emoji is in allowed list
      unless MessageReaction::REACTIONS.include?(emoji)
        head :unprocessable_entity
        return
      end

      added = message.toggle_reaction!(Current.user, emoji)

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "reactions_#{message.id}",
            partial: "shared/messages/reactions",
            locals: { message: message }
          )
        end
        format.html { redirect_back fallback_location: manage_message_path(message.root_message) }
      end
    end

    # DELETE /manage/messages/:id
    def destroy
      message = Message.find_by(id: params[:id])

      if message.nil?
        redirect_to manage_messages_path, alert: "Message not found"
        return
      end

      unless message.can_be_deleted_by?(Current.user)
        redirect_back fallback_location: manage_messages_path, alert: "You can only delete your own messages"
        return
      end

      root = message.root_message
      is_root = message.parent_message_id.nil?

      message.smart_delete!

      if is_root
        redirect_to manage_messages_path, notice: "Message deleted"
      else
        redirect_to manage_message_path(root), notice: "Reply deleted"
      end
    end

    private

    def message_not_found
      redirect_to manage_messages_path, alert: "Message not found"
    end
  end
end
