class Message < ApplicationRecord
  belongs_to :sender, polymorphic: true  # User or Person
  belongs_to :organization, optional: true
  belongs_to :production, optional: true  # Direct FK for visibility scoping
  belongs_to :show, optional: true        # Direct FK for visibility scoping

  # Threading relationships
  belongs_to :parent_message, class_name: "Message", optional: true
  has_many :child_messages, class_name: "Message", foreign_key: :parent_message_id, dependent: :destroy

  # Recipients (replaces single recipient + batch pattern)
  has_many :message_recipients, dependent: :destroy
  has_many :recipient_people, through: :message_recipients, source: :recipient, source_type: "Person"
  has_many :recipient_groups, through: :message_recipients, source: :recipient, source_type: "Group"

  # Thread subscriptions (who sees this in their inbox)
  has_many :message_subscriptions, dependent: :destroy
  has_many :subscribers, through: :message_subscriptions, source: :user

  # Reactions
  has_many :message_reactions, dependent: :destroy

  # Poll
  has_one :message_poll, dependent: :destroy
  accepts_nested_attributes_for :message_poll, reject_if: proc { |attrs| attrs["question"].blank? }

  # Multi-regarding support (additional context objects)
  has_many :message_regards, dependent: :destroy

  has_rich_text :body
  has_many_attached :images

  # Visibility determines who can see the message
  enum :visibility, {
    personal: "private",      # Only sender + recipients
    production: "production", # All production managers/viewers + recipients
    show: "show"              # Production team + that show's cast
  }, default: :personal

  # Message type for categorization
  enum :message_type, {
    cast_contact: "cast_contact",         # Manager → cast about a show
    talent_pool: "talent_pool",           # Manager → talent pool members
    direct: "direct",                     # Person → person (private)
    production_contact: "production_contact", # Cast → production team
    system: "system"                      # System notifications
  }

  validates :subject, presence: true, length: { maximum: 255 }
  validates :message_type, presence: true

  # Callbacks for real-time updates
  after_create_commit :broadcast_to_thread
  after_create_commit :notify_subscribers

  # Scopes
  scope :root_messages, -> { where(parent_message_id: nil) }
  scope :not_deleted, -> { where(deleted_at: nil) }

  # Soft delete methods
  def deleted?
    deleted_at.present?
  end

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  # Delete message - soft delete if has children, hard delete if leaf
  def smart_delete!
    if child_messages.exists?
      soft_delete!
    else
      destroy!
    end
  end

  # Check if user can delete this message
  def can_be_deleted_by?(user)
    return false unless user
    # User is the sender
    return true if sender_type == "User" && sender_id == user.id
    # User's person is the sender
    return true if sender_type == "Person" && user.person&.id == sender_id
    false
  end

  # Check if user can view read receipts for this message
  # - Sender can always see read receipts for messages they sent
  # - Production/org team members can see read receipts for production messages
  def can_view_read_receipts_by?(user)
    return false unless user
    return false if message_recipients.empty?

    # Sender can always see read receipts
    return true if sender_type == "User" && sender_id == user.id
    return true if sender_type == "Person" && user.person&.id == sender_id

    # For production messages, team members can view read receipts
    if production.present?
      return true if ::ProductionPermission.exists?(production: production, user: user)
      return true if ::OrganizationRole.exists?(organization: production.organization, user: user)
    end

    false
  end

  # Messages visible to a user based on subscriptions
  scope :subscribed_by, ->(user) {
    joins(:message_subscriptions).where(message_subscriptions: { user: user, muted: false })
  }

  # Production-scoped messages (for manage/messages)
  scope :for_production, ->(production) {
    where(production: production, visibility: [ :production, :show ])
  }

  # Show-scoped messages
  scope :for_show, ->(show) {
    where(show: show, visibility: :show)
  }

  # Messages where user is a recipient
  scope :received_by, ->(user) {
    person_ids = user.people.pluck(:id)
    joins(:message_recipients).where(message_recipients: { recipient_type: "Person", recipient_id: person_ids })
  }

  # Messages not archived by a specific recipient
  scope :active_for_recipient, ->(person) {
    joins(:message_recipients)
      .where(message_recipients: { recipient: person, archived_at: nil })
  }

  # Add regardable objects to this message
  def add_regards(*regardables)
    regardables.flatten.compact.each do |regardable|
      # Use find + create to avoid Rails 8.1 upsert issues with scoped associations
      existing = message_regards.find_by(
        regardable_type: regardable.class.name,
        regardable_id: regardable.id
      )
      unless existing
        message_regards.create!(
          regardable_type: regardable.class.name,
          regardable_id: regardable.id
        )
      end
    end
  end

  # Get all regardable objects for this message
  def regardables
    message_regards.includes(:regardable).map(&:regardable).compact
  end

  def reply?
    parent_message_id.present?
  end

  # Calculate depth in the thread (0 = root, 1 = direct reply, etc.)
  def thread_depth
    depth = 0
    msg = self
    while msg.parent_message_id.present?
      depth += 1
      msg = msg.parent_message
    end
    depth
  end

  # Human-readable sender name
  # For production/show-scoped messages, show "Production Team" or production name
  def sender_name
    if sent_as_production_team?
      production&.name || "Production Team"
    else
      case sender
      when User then sender.person&.name || sender.email_address
      when Person then sender.name
      else "CocoScout"
      end
    end
  end

  # Whether this message was sent "as the production team" (visible to team, not personal)
  def sent_as_production_team?
    %w[production show].include?(visibility) && %w[cast_contact talent_pool].include?(message_type)
  end

  # Get recipient count
  def recipient_count
    message_recipients.count
  end

  # Get recipient names (for display)
  def recipient_names
    message_recipients.includes(:recipient).map { |mr| mr.recipient&.name }.compact
  end

  # Check if a person is a recipient
  def recipient?(person)
    message_recipients.exists?(recipient: person)
  end

  # Mark as read for a specific person
  def mark_read_for!(person)
    message_recipients.find_by(recipient: person)&.mark_read!
  end

  # Check if unread for a specific person
  def unread_for?(person)
    mr = message_recipients.find_by(recipient: person)
    mr.nil? || mr.read_at.nil?
  end

  # Archive for a specific person
  def archive_for!(person)
    message_recipients.find_by(recipient: person)&.archive!
  end

  # Reaction helpers
  def reaction_counts
    message_reactions.group(:emoji).count
  end

  def user_reaction(user)
    message_reactions.find_by(user: user)&.emoji
  end

  def add_reaction!(user, emoji)
    # Use find + create to avoid Rails 8.1 upsert issues with scoped associations
    existing = message_reactions.find_by(user: user, emoji: emoji)
    existing || message_reactions.create!(user: user, emoji: emoji)
  end

  def remove_reaction!(user, emoji)
    message_reactions.find_by(user: user, emoji: emoji)&.destroy
  end

  def toggle_reaction!(user, emoji)
    existing = message_reactions.find_by(user: user)

    if existing
      if existing.emoji == emoji
        # Same reaction - remove it (toggle off)
        existing.destroy
        false
      else
        # Different reaction - replace it
        existing.update!(emoji: emoji)
        true
      end
    else
      # No existing reaction - add new one
      message_reactions.create!(user: user, emoji: emoji)
      true
    end
  end

  # Get the root message of this thread
  def root_message
    return self if parent_message_id.nil?

    current = self
    current = current.parent_message while current.parent_message_id.present?
    current
  end

  # Get all descendant message IDs (recursive)
  def descendant_ids
    child_ids = child_messages.pluck(:id)
    return child_ids if child_ids.empty?

    child_ids + Message.where(id: child_ids).flat_map(&:descendant_ids)
  end

  # Get all descendant messages (recursive)
  def descendant_messages
    Message.where(id: descendant_ids)
  end

  # Get all messages in this thread (including root)
  def thread_messages
    root = root_message
    Message.where(id: [ root.id ] + root.descendant_ids)
  end

  # Thread subscription management
  def subscribe!(user, mark_read: false)
    return unless user
    root = root_message
    # Use find + create to avoid Rails 8.1 upsert issues with scoped associations
    subscription = MessageSubscription.find_by(user: user, message: root)
    subscription ||= MessageSubscription.create!(user: user, message: root)
    subscription.mark_read! if mark_read
    subscription
  end

  def unsubscribe!(user)
    root = root_message
    MessageSubscription.find_by(user: user, message: root)&.destroy
  end

  def subscribed?(user)
    return false unless user
    root = root_message
    MessageSubscription.exists?(user: user, message: root)
  end

  # Subscribe all managers/viewers of the production
  def subscribe_production_team!
    return unless production

    # Global org managers/viewers
    production.organization.organization_roles.where(company_role: [ :manager, :viewer ]).find_each do |role|
      subscribe!(role.user)
    end

    # Production-specific permissions
    production.production_permissions.where(role: [ :manager, :viewer ]).find_each do |permission|
      subscribe!(permission.user)
    end
  end

  # Get count of unread messages in this thread for a user
  def unread_count_for(user)
    subscription = root_message.message_subscriptions.find_by(user: user)
    return 0 unless subscription

    last_read = subscription.last_read_at || Time.at(0)
    root = root_message
    Message.where(id: [ root.id ] + root.descendant_ids)
           .where("created_at > ?", last_read)
           .count
  end

  # Get latest activity timestamp in thread
  def latest_activity_at
    root = root_message
    latest = root.descendant_messages.maximum(:created_at)
    latest || root.created_at
  end

  # Context card info based on production/show
  def regarding_context
    if show.present?
      {
        type: :show,
        title: show.production.name,
        subtitle: show.formatted_date_and_time,
        location: show.display_location,
        image: show.production.posters.primary.first&.safe_image_variant(:small)
      }
    elsif production.present?
      {
        type: :production,
        title: production.name,
        image: production.logo
      }
    else
      nil
    end
  end

  private

  # Broadcast new reply to all viewers of the thread
  def broadcast_to_thread
    return unless reply? # Only broadcast for replies

    root = root_message
    html = ApplicationController.render(
      partial: "shared/messages/nested_reply",
      locals: { reply: self, depth: calculate_depth }
    )

    MessageThreadChannel.broadcast_to(
      root,
      type: "new_reply",
      html: html,
      sender_id: sender.is_a?(User) ? sender.id : nil,
      message_id: id
    )
  rescue ArgumentError => e
    # Solid Cable in Rails 8.1 has upsert compatibility issues
    Rails.logger.warn("Message#broadcast_to_thread failed: #{e.message}")
  end

  # Notify all subscribers about the new message (increment unread counts)
  def notify_subscribers
    root = root_message
    sender_user = sender.is_a?(User) ? sender : nil

    root.message_subscriptions.includes(:user).find_each do |subscription|
      next if subscription.user == sender_user # Don't notify sender

      # Increment unread count for this subscription
      subscription.increment_unread!

      UserNotificationsChannel.broadcast_unread_count(subscription.user)

      # Also send new message notification if not muted
      unless subscription.muted?
        UserNotificationsChannel.broadcast_new_message(
          subscription.user,
          self,
          root.subject
        )
      end
    end
  end

  # Calculate depth for nested reply rendering
  def calculate_depth
    depth = 0
    current = parent_message
    while current && current != root_message
      depth += 1
      current = current.parent_message
    end
    depth
  end
end
