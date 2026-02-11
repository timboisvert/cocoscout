# Message Read/Unread System Strategy

## Executive Summary

This document provides a comprehensive analysis of the message read/unread tracking system in CocoScout, identifies current issues, and proposes a unified strategy for improvement.

---

## Current Architecture

### Core Models

#### 1. Message
- Represents individual messages in conversations
- Belongs to a `conversation` and has many `message_recipients`
- Key fields: `body`, `sender_id`, `conversation_id`, `created_at`

#### 2. MessageRecipient
- Join table linking messages to recipient users
- **Key field**: `read_at` - timestamp when recipient read this specific message
- Scope: `unread` → `where(read_at: nil)`

#### 3. MessageSubscription
- Links users to conversations they're subscribed to
- **Key field**: `last_read_at` - timestamp of when user last viewed the conversation
- Used for thread-level read tracking

#### 4. Conversation
- Container for messages between participants
- Has many `messages`, `message_subscriptions`, and `participants`

---

## Dual Read Tracking System

The system currently uses **two parallel approaches** to track read status:

### Approach A: Per-Message Tracking (MessageRecipient)
```ruby
# Each message has individual read status per recipient
message_recipient.read_at = Time.current
```

**Pros:**
- Granular tracking of exactly which messages were read
- Can show "X unread messages" count accurately

**Cons:**
- More database writes (one per message per recipient)
- Requires updating multiple records when opening a conversation

### Approach B: Subscription-Level Tracking (MessageSubscription)
```ruby
# Track when user last viewed the conversation
subscription.last_read_at = Time.current
# Unread = messages created after last_read_at
```

**Pros:**
- Single record update when viewing conversation
- Efficient for "has unread" boolean checks
- Natural for email digest logic

**Cons:**
- Less granular (can't count exact unread messages as easily)

---

## Current Implementation Analysis

### Where Read Status Is Set

#### 1. MessagesController#index (viewing a conversation)
```ruby
# Updates subscription-level tracking
@subscription.touch(:last_read_at)

# Also marks individual messages as read
@conversation.messages.each do |message|
  recipient = message.message_recipients.find_by(user: current_user)
  recipient&.update(read_at: Time.current) if recipient&.read_at.nil?
end
```

#### 2. ConversationsController (various actions)
- Similar dual-update pattern when viewing conversations

### Where Unread Count Is Calculated

#### User#unread_message_count
```ruby
def unread_message_count
  message_recipients.unread.count
end
```
- Uses MessageRecipient approach
- **⚠️ N+1 ISSUE**: This queries the database each time it's called

#### UnreadDigestJob (Email Digests)
```ruby
# Uses subscription-level approach
subscriptions_with_unread = user.message_subscriptions
  .where("last_read_at < conversations.updated_at OR last_read_at IS NULL")
```

---

## Identified Issues

### 1. Inconsistent Read Tracking Source
- UI badge uses `MessageRecipient#read_at`
- Email digest uses `MessageSubscription#last_read_at`
- These can get out of sync

### 2. N+1 Performance Problem
```ruby
# In User model - potentially slow
def unread_message_count
  message_recipients.unread.count  # OK, but called frequently
end
```

The real issue is in views/controllers that call this repeatedly:
```erb
<% users.each do |user| %>
  <%= user.unread_message_count %>  <!-- N+1 query -->
<% end %>
```

### 3. Dual Update Overhead
When marking messages as read, the system updates BOTH:
- Each `MessageRecipient.read_at` (N updates)
- The `MessageSubscription.last_read_at` (1 update)

### 4. Race Conditions
- Real-time ActionCable updates may conflict with background job calculations
- No locking mechanism for concurrent read operations

---

## Proposed Strategy

### Phase 1: Establish Single Source of Truth

**Recommendation**: Use `MessageSubscription#last_read_at` as the primary source for unread calculations.

**Rationale:**
- More efficient (one record per user per conversation)
- Naturally handles "mark all as read" scenarios
- Aligns with email digest logic
- Better for real-time UI updates

**Migration Path:**
1. Keep `MessageRecipient#read_at` for historical/audit purposes
2. Update `User#unread_message_count` to use subscription-based calculation
3. Simplify mark-as-read to only update subscription

### Phase 2: Optimize Unread Count Query

```ruby
# Proposed new implementation
def unread_message_count
  message_subscriptions
    .joins(:conversation)
    .where("message_subscriptions.last_read_at < conversations.updated_at
            OR message_subscriptions.last_read_at IS NULL")
    .joins("INNER JOIN messages ON messages.conversation_id = conversations.id")
    .where("messages.created_at > COALESCE(message_subscriptions.last_read_at, '1970-01-01')")
    .where.not(messages: { sender_id: id })
    .count
end
```

Or simpler approach with counter cache:
```ruby
# Add to MessageSubscription
add_column :message_subscriptions, :unread_count, :integer, default: 0

# Update on new message
after_create :increment_recipient_unread_counts
# Update on read
subscription.update(unread_count: 0, last_read_at: Time.current)
```

### Phase 3: Unify Real-Time and Background Updates

```ruby
# Single method for marking conversation as read
class MessageSubscription < ApplicationRecord
  def mark_as_read!
    transaction do
      update!(last_read_at: Time.current, unread_count: 0)
      # Broadcast updated count
      UserNotificationsChannel.broadcast_unread_count(user)
    end
  end
end
```

### Phase 4: Clean Up Redundant Code

1. ~~Deprecate per-message `read_at` updates in controllers~~ **KEPT** - Required for Read Receipts feature
2. ~~Remove dual-tracking in `MessagesController#index`~~ **KEPT** - `mark_read_for!` needed for read receipts, `mark_read!` for unread counts
3. Consolidate read-marking logic into `MessageSubscription#mark_as_read!` ✅

**Note:** The dual-tracking serves different purposes:
- `MessageSubscription.unread_count` → Badge counts and unread indicators (optimized)
- `MessageRecipient.read_at` → Read Receipts feature (shows who read when)

---

## Implementation Checklist

- [x] Add `unread_count` column to `message_subscriptions` table
- [x] Create migration with backfill of existing unread counts
- [x] Update `User#unread_message_count` to use new column
- [x] Update `MessagesController` to use `subscription.mark_as_read!`
- [x] Update `ConversationsController` similarly
- [x] Update message creation to increment `unread_count` for recipients
- [x] Update `UnreadDigestJob` to use unified logic
- [x] Add ActionCable broadcast on unread count change
- [x] Add database index on `message_subscriptions(user_id, unread_count)`
- [ ] Write comprehensive tests for edge cases
- [ ] Monitor performance after deployment

---

## Edge Cases to Handle

1. **User joins conversation mid-thread**: Initialize `last_read_at` to current time or show all as unread?
2. **Sender viewing their own message**: Don't count sender's messages as unread for them
3. **Deleted messages**: Should decrement unread count if message was unread
4. **Conversation archival**: Preserve or clear unread state?
5. **Multiple devices**: Ensure real-time sync across all user sessions

---

## Testing Strategy

### Unit Tests
- `MessageSubscription#mark_as_read!` correctly updates timestamp and count
- `User#unread_message_count` returns correct count
- New message increments correct subscriptions

### Integration Tests
- Opening conversation marks all messages as read
- Real-time badge updates when new message arrives
- Digest email only includes truly unread conversations

### Performance Tests
- Benchmark unread count query with 1000+ conversations
- Load test ActionCable broadcasts with many concurrent users

---

## Rollback Plan

If issues arise after deployment:
1. Feature flag to switch between old/new unread calculation
2. Keep `MessageRecipient#read_at` populated during transition
3. Can revert to per-message tracking if subscription approach fails

---

## Timeline Estimate

- Phase 1 (Single Source): 2-3 days
- Phase 2 (Optimization): 1-2 days
- Phase 3 (Real-Time): 1 day
- Phase 4 (Cleanup): 1 day
- Testing & QA: 2-3 days

**Total**: ~1-2 weeks for full implementation

---

## Related Files

### Models
- `app/models/message.rb`
- `app/models/message_recipient.rb`
- `app/models/message_subscription.rb`
- `app/models/conversation.rb`
- `app/models/user.rb`

### Controllers
- `app/controllers/messages_controller.rb`
- `app/controllers/conversations_controller.rb`

### Jobs
- `app/jobs/unread_digest_job.rb`

### Channels
- `app/channels/user_notifications_channel.rb`

### Views
- Navigation partials showing unread badges
- Message inbox views
