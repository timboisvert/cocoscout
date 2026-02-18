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
      # Excludes system-generated messages (automated notifications)
      private_received_ids = Message.joins(:message_recipients)
                                    .where(message_recipients: { recipient_type: "Person", recipient_id: person_ids })
                                    .select(:id)

      @messages = Message
        .where(organization: Current.organization)
        .where(system_generated: false)
        .root_messages
        .where(
          "(messages.visibility IN (?) AND messages.production_id IN (?)) OR " +
          "(messages.visibility = ? AND messages.sender_type = ? AND messages.sender_id = ?) OR " +
          "(messages.visibility = ? AND messages.id IN (?))",
          [ "production", "show" ], accessible_production_ids,
          "private", "User", Current.user.id,
          "private", private_received_ids
        )
        .includes(:sender, :message_recipients, :child_messages, :production, :show, :message_poll, images_attachments: :blob)

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

      # Unread count scoped to this organization's messages
      org_message_ids = Message.where(organization: Current.organization).pluck(:id)
      @unread_count = Current.user.message_subscriptions.unread.where(message_id: org_message_ids).count
    end

    # GET /manage/messages/production/:production_id
    def production
      @production = Current.user.accessible_productions
                                .where(organization: Current.organization)
                                .find(params[:production_id])

      # Get all messages for this production (production + show scoped, plus private messages)
      # Excludes system-generated messages (automated notifications)
      person_ids = Current.user.people.pluck(:id)
      private_received_ids = Message.joins(:message_recipients)
                                    .where(message_recipients: { recipient_type: "Person", recipient_id: person_ids })
                                    .select(:id)

      @messages = Message
        .where(production: @production)
        .where(system_generated: false)
        .root_messages
        .where(
          "visibility IN (?) OR " +
          "(visibility = ? AND sender_type = ? AND sender_id = ?) OR " +
          "(visibility = ? AND id IN (?))",
          [ "production", "show" ],
          "private", "User", Current.user.id,
          "private", private_received_ids
        )
        .includes(:sender, :message_recipients, :child_messages, :show, :message_poll, images_attachments: :blob)
        .order(updated_at: :desc)
        .limit(100)

      @hide_production_via = true  # Don't show "via" since we're already filtered by production
      render :production
    end

    def show
      @message = Message.find(params[:id])
      @root_message = @message.root_message

      # Clear focus param if trying to comment on a deleted message
      if @root_message.deleted? && params[:focus] == "comment"
        redirect_to manage_message_path(@root_message) and return
      end

      # Mark as read for user's person if they're a recipient
      # A user can have multiple Person records (one per org), so find the one
      # that's actually a recipient on this message
      if Current.user.people.any?
        recipient_person = @root_message.message_recipients
                            .where(recipient_type: "Person", recipient_id: Current.user.people.select(:id))
                            .first&.recipient
        recipient_person&.then { |p| @root_message.mark_read_for!(p) }
      end

      # Mark subscription as read
      subscription = @root_message.message_subscriptions.find_by(user: Current.user)
      subscription&.mark_read!

      # Load all messages in thread
      @thread_messages = Message.where(id: [ @root_message.id ] + @root_message.descendant_ids)
                                .includes(:sender, :message_recipients, message_poll: :message_poll_options)
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
        attach_poll!(message) if poll_params_present?
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
        attach_poll!(message) if poll_params_present?
        redirect_to manage_messages_path, notice: "Message sent to #{group.name}"

      when "show_cast"
        show = Show.joins(:production).where(productions: { organization_id: Current.organization.id }).find(recipient_id)
        # Determine visibility based on sender_identity param
        # production_team (default) = :show (team + show cast), personal = :personal (only sender + recipients)
        visibility = params[:sender_identity] == "personal" ? :personal : :show
        message = MessageService.send_to_show_cast(
          show: show,
          sender: Current.user,
          subject: subject,
          body: body,
          visibility: visibility
        )
        message&.images&.attach(images) if images.present?
        attach_poll!(message) if poll_params_present?
        redirect_to manage_messages_path, notice: "Message sent to #{show.display_name} cast"

      when "auditionees"
        audition_cycle = AuditionCycle.joins(:production).where(productions: { organization_id: Current.organization.id }).find(recipient_id)
        # Get all active auditionees (people with active audition requests)
        people = audition_cycle.audition_requests.active.map(&:person).compact.uniq
        send_separately = params[:send_separately] == "1" || params[:send_separately] == "on"
        # Determine visibility based on sender_identity param
        visibility = params[:sender_identity] == "personal" ? :personal : :production

        if people.empty?
          redirect_back fallback_location: manage_messages_path, alert: "No auditionees found for this audition cycle"
          return
        end

        if send_separately
          # Send individual messages to each auditionee
          messages_sent = 0
          people.each do |person|
            message = MessageService.send_to_people(
              sender: Current.user,
              people: [ person ],
              subject: subject,
              body: body,
              message_type: :direct,
              production: audition_cycle.production,
              organization: Current.organization,
              visibility: visibility
            )
            if message
              message.images.attach(images) if images.present?
              messages_sent += 1
            end
          end
          redirect_to manage_messages_path, notice: "Sent #{messages_sent} individual #{'message'.pluralize(messages_sent)} to auditionees."
        else
          message = MessageService.send_to_people(
            sender: Current.user,
            people: people,
            subject: subject,
            body: body,
            message_type: :direct,
            production: audition_cycle.production,
            organization: Current.organization,
            visibility: visibility
          )
          message&.images&.attach(images) if images.present?
          attach_poll!(message) if poll_params_present?
          redirect_to manage_messages_path, notice: "Message sent to #{people.count} #{'auditionee'.pluralize(people.count)}"
        end

      when "talent_pool"
        production_id = params[:production_id]
        production = production_id.present? ? Current.organization.productions.find(production_id) : nil
        talent_pool = production&.effective_talent_pool || TalentPool.find(recipient_id)

        # Get all people in the talent pool
        people = Person.joins(:talent_pool_memberships)
                       .where(talent_pool_memberships: { talent_pool_id: talent_pool.id })
                       .distinct

        if people.empty?
          redirect_back fallback_location: manage_messages_path, alert: "No members found in #{talent_pool.name}"
          return
        end

        # Determine visibility based on sender_identity param
        # production_team (default) = :production (all team), personal = :personal (only sender + recipients)
        visibility = params[:sender_identity] == "personal" ? :personal : :production
        message = MessageService.send_to_people(
          sender: Current.user,
          people: people.to_a,
          subject: subject,
          body: body,
          message_type: :talent_pool,
          production: production,
          organization: Current.organization,
          visibility: visibility
        )
        message&.images&.attach(images) if images.present?
        attach_poll!(message) if poll_params_present?
        redirect_to manage_messages_path, notice: "Message sent to #{people.count} #{'member'.pluralize(people.count)} in #{talent_pool.name}"

      when "batch"
        # Handle batch messaging from directory selection or agreement reminders
        person_ids = params[:person_ids]&.select(&:present?) || []
        send_separately = params[:send_separately] == "1" || params[:send_separately] == "on"
        # Determine visibility based on sender_identity param
        visibility = params[:sender_identity] == "personal" ? :personal : :production

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
            message = MessageService.send_to_people(
              sender: Current.user,
              people: [ person ],
              subject: subject,
              body: body,
              message_type: :direct,
              organization: Current.organization,
              visibility: visibility
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
            organization: Current.organization,
            visibility: visibility
          )
          message&.images&.attach(images) if images.present?
          attach_poll!(message) if poll_params_present?
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

      # Prevent replying to deleted messages
      if parent.deleted?
        redirect_to manage_message_path(root_message), alert: "Cannot reply to a deleted message"
        return
      end

      # Ensure user has access (subscribed to thread)
      unless root_message.subscribed?(Current.user)
        redirect_to manage_messages_path, alert: "You don't have access to this thread"
        return
      end

      # Determine visibility from sender_identity param
      # "production_team" -> inherit from root, "personal" -> personal visibility
      visibility = if params[:sender_identity] == "personal"
        "personal"
      else
        nil # inherit from root message
      end

      message = MessageService.reply(
        sender: Current.user,
        parent_message: parent,
        body: params[:body],
        visibility: visibility
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

    # POST /manage/messages/:id/vote_poll
    def vote_poll
      message = Message.find(params[:id])
      poll = message.message_poll

      unless poll
        redirect_back fallback_location: manage_messages_path, alert: "No poll found"
        return
      end

      option = poll.message_poll_options.find_by(id: params[:option_id])
      unless option
        redirect_back fallback_location: manage_message_path(message.root_message), alert: "Invalid poll option"
        return
      end

      unless poll.accepting_votes?
        redirect_back fallback_location: manage_message_path(message.root_message), alert: "This poll is closed"
        return
      end

      existing_vote = option.message_poll_votes.find_by(user: Current.user)
      if existing_vote
        # Toggle off - remove vote
        existing_vote.destroy!
      else
        # For single-vote polls (max_votes = 1), remove any existing vote first
        if poll.max_votes == 1
          poll.message_poll_votes.where(user: Current.user).destroy_all
        end

        # Add vote (max_votes validated in model for multi-vote polls)
        vote = option.message_poll_votes.new(user: Current.user)
        unless vote.save
          redirect_back fallback_location: manage_message_path(message.root_message), alert: vote.errors.full_messages.first
          return
        end
      end

      redirect_back fallback_location: manage_message_path(message.root_message)
    end

    # POST /manage/messages/:id/close_poll
    def close_poll
      message = Message.find(params[:id])
      poll = message.message_poll

      unless poll && poll.created_by?(Current.user)
        redirect_back fallback_location: manage_messages_path, alert: "Only the poll creator can close it"
        return
      end

      poll.close!
      redirect_back fallback_location: manage_message_path(message.root_message), notice: "Poll closed"
    end

    private

    def message_not_found
      redirect_to manage_messages_path, alert: "Message not found"
    end

    def poll_params_present?
      params[:message_poll].present? && params[:message_poll][:question].present?
    end

    def attach_poll!(message)
      return unless message && poll_params_present?

      poll_attrs = params.require(:message_poll).permit(
        :question, :max_votes,
        message_poll_options_attributes: [ :text, :position ]
      ).to_h

      # Default max_votes to 1 if not set
      poll_attrs["max_votes"] ||= 1

      # Filter out blank options
      if poll_attrs["message_poll_options_attributes"]
        poll_attrs["message_poll_options_attributes"] = poll_attrs["message_poll_options_attributes"]
          .values
          .reject { |opt| opt["text"].blank? }
          .each_with_index.map { |opt, i| opt.merge("position" => i) }
      end

      message.create_message_poll!(poll_attrs)
    end
  end
end
