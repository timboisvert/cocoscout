# Messaging System Overhaul Plan

## Overview

This plan transforms CocoScout's communication from scattered email-based messaging to a unified in-app messaging system. Users will receive messages in an in-app inbox with notifications, and only get email reminders if messages remain unread after a delay.

---

## Part 1: Forum Infrastructure to Remove (100%)

### Database Tables & Models

| File/Table | Action |
|------------|--------|
| `app/models/post.rb` | DELETE |
| `app/models/post_view.rb` | DELETE |
| Create new migration: `drop_posts_and_post_views` | Drop `posts` and `post_views` tables |

### Controllers to DELETE

| File | Action |
|------|--------|
| `app/controllers/my/messages_controller.rb` | DELETE (forum methods: index, create, reply_form, posts) |

Note: The `emails`, `show`, and `send_message` actions in messages_controller will be replaced by the new inbox system.

### Views to DELETE

**Forum views (my/messages):**
| File | Action |
|------|--------|
| `app/views/my/messages/` | DELETE entire directory |

**Communications views (manage):**
| File | Action |
|------|--------|
| `app/views/manage/communications/` | DELETE entire directory |
| `app/views/manage/org_communications/` | DELETE entire directory |

### Routes to REMOVE

```ruby
# In config/routes.rb - REMOVE ALL of these:

# My namespace - ALL /my/messages routes
get   "/messages",              to: "messages#index"      # Forum list
post  "/messages",              to: "messages#create"     # Create post
get   "/messages/reply_form",   to: "messages#reply_form" # Reply form
get   "/messages/posts",        to: "messages#posts"      # Forum posts
get   "/messages/emails",       to: "messages#emails"     # Email list (DELETE)
get   "/messages/:id",          to: "messages#show"       # Email detail (DELETE)
post  "/messages/send",         to: "messages#send_message" # Send to production (DELETE)

# Manage namespace - ALL /manage/communications routes
get  "/communications",     to: "org_communications#index"
post "/communications/send_message", to: "org_communications#send_message"
get  "/communications/talent_pool_members/:production_id", to: "org_communications#talent_pool_members"
get  "/communications/:production_id", to: "communications#index"
get  "/communications/:production_id/:id", to: "communications#show"
post "/communications/:production_id/send_message", to: "communications#send_message"

# MOVE questionnaires from /communications to /casting:
# OLD: /manage/communications/:production_id/questionnaires/*
# NEW: /manage/casting/:production_id/questionnaires/*
```

### Routes to ADD

```ruby
# New inbox routes
namespace :my do
  resources :inbox, only: [:index, :show] do
    member do
      post :archive
      post :mark_read
    end
    collection do
      post :mark_all_read
    end
  end
end
```

### Routes to MOVE (Questionnaires)

Move all questionnaire routes from `/communications` to `/casting`:

```ruby
# OLD (delete these):
get  "/communications/:production_id/questionnaires", to: "questionnaires#index"
get  "/communications/:production_id/questionnaires/new", to: "questionnaires#new"
# ... etc

# NEW (add these under casting namespace):
scope "/casting/:production_id" do
  resources :questionnaires do
    member do
      get :form
      get :preview
      post :create_question
      # ... etc (same actions, new URL prefix)
    end
  end
end
```

**Also update:**
- All `_path` helpers in views: `manage_communications_questionnaires_path` → `manage_casting_questionnaires_path`
- Breadcrumbs in questionnaire views to reference Casting instead of Communications

### Model Fields to Remove

| Model | Field | Action |
|-------|-------|--------|
| `Organization` | `forum_mode` (enum) | Remove column, remove enum definition |
| `Organization` | `shared_forum_name` | Remove column |
| `Production` | `forum_enabled` (boolean) | Remove column |

### Organization Model Changes

Remove from `app/models/organization.rb`:
```ruby
# Line 26-28: Remove forum_mode enum
enum :forum_mode, {
  per_production: "per_production",
  shared: "shared"
}

# Line 45: Remove forum_display_name method
def forum_display_name
  shared_forum_name.presence || name
end
```

### Controllers to Modify

| File | Change |
|------|--------|
| `app/controllers/manage/organizations_controller.rb:144` | Remove `forum_enabled` toggle handling |
| `app/controllers/manage/organizations_controller.rb:161` | Remove `forum_mode`, `shared_forum_name` from permitted params |

### Related Code to Clean Up

- Remove `has_many :posts` associations from Production, Person models
- Remove forum links from navigation (My sidebar)
- Remove `forum_shared?` method calls

---

## Part 2: Email Infrastructure Changes

### Emails to KEEP (Transactional/Account-Related)

These are tied to specific system actions and should remain as emails:

| Mailer | Method | Purpose |
|--------|--------|---------|
| `AuthMailer` | All methods | Password reset, email confirmation |
| `UserMailer` | `invitation` | Account invitations |
| `UserMailer` | `email_verification` | Email verification |
| `CastingNotificationMailer` | All methods | Casting decisions (accept/reject) |
| `ShowMailer` | `cancellation_notice` | Show cancellations |
| `VacancyNotificationMailer` | All methods | Vacancy invitations |
| `SignUpConfirmationMailer` | All methods | Audition/ticket confirmations |
| `TicketMailer` | All methods | Ticket purchases |
| `ReminderMailer` | All methods | Automated reminders |
| `TestMailer` | All methods | System testing |

### Controllers to DELETE ENTIRELY

These controllers exist primarily for email viewing/sending - delete them completely:

| Controller | Current Purpose | Why Delete |
|------------|-----------------|------------|
| `Manage::CommunicationsController` | View sent emails + send to talent pool | New inbox replaces; send becomes MessageService |
| `Manage::OrgCommunicationsController` | View org emails + send to org people | New inbox replaces; send becomes MessageService |
| `My::MessagesController` | Forum + view received emails + send to production | Forum deleted; inbox replaces email viewing |

**Note:** Superadmin email logs stay - only user-facing email history views are removed.

### Where to Add "Send Message" Buttons

Since we're removing the communications pages, the "Send Message" functionality moves to:

| Context | Location | Action |
|---------|----------|--------|
| Contact talent pool | Production settings or talent pool page | Opens compose modal with `regarding: @production` |
| Contact cast | Show detail page | Opens compose modal with `regarding: @show` |
| Contact person | Person profile modal | Opens compose modal (direct message) |

#### Controller Conversion Examples

**Before (Manage::CommunicationsController#send_message):**
```ruby
people_to_email.each do |person|
  Manage::ProductionMailer.send_message(
    person, prefixed_subject, body_html, Current.user,
    email_batch_id: email_batch&.id, production_id: @production.id
  ).deliver_later
end
```

**After:**
```ruby
MessageService.send_to_talent_pool(
  production: @production,
  sender: Current.user,
  subject: subject,
  body: body_html,
  person_ids: person_ids.presence  # nil = all talent pool
)
redirect_to manage_communications_production_path(@production),
            notice: "Message sent to #{people_to_email.count} recipients."
```

**Before (My::MessagesController#send_message for talent→production):**
```ruby
My::TalentMessageMailer.send_to_production(
  sender: Current.user.person,
  production: production,
  subject: rendered_subject,
  body_html: rendered_body
).deliver_later
```

**After:**
```ruby
# Find production managers to receive the message
production.managers.each do |manager_user|
  MessageService.send_direct(
    sender: Current.user.person,
    recipient_user: manager_user,
    subject: subject,
    body: body_html,
    organization: production.organization
  )
end
redirect_back fallback_location: my_production_path(production),
              notice: "Message sent to #{production.name} team."
```

### Mailers to DELETE (replaced by MessageService)

These mailer methods will be completely replaced by `MessageService` and can be deleted:

| Mailer | Method | Replaced By |
|--------|--------|-------------|
| `Manage::ProductionMailer` | `send_message` | `MessageService.send_to_talent_pool` |
| `CommunicationsMailer` | `send_message` | `MessageService.send_to_talent_pool` |
| `My::TalentMessageMailer` | `send_to_production` | `MessageService.send_direct` |

### New Mailer for Reminders Only

The only new mailer is for delayed "you have unread messages" reminders:

### Email Templates to Keep (for now, then delete after in-app works)

Wait until in-app messaging is fully working, then delete:
- `app/views/manage/production_mailer/send_message.html.erb`
- `app/views/my/talent_message_mailer/send_to_production.html.erb`
- `app/views/my/talent_message_mailer/send_to_production.text.erb`

### Email Templates to KEEP (Transactional)

Keep all contact_email templates (these are for direct contact, not open messaging):
- `app/views/manage/person_mailer/contact_email.html.erb`
- `app/views/manage/person_mailer/contact_email.text.erb`
- `app/views/manage/person_mailer/person_invitation.html.erb`
- `app/views/manage/person_mailer/person_invitation.text.erb`

### Email Infrastructure to Keep

| Model/File | Purpose | Action |
|------------|---------|--------|
| `EmailLog` | Tracks sent emails | KEEP (for transactional emails) |
| `EmailDraft` | Draft emails | KEEP (still useful for composing) |
| `EmailTemplate` | Reusable templates | KEEP (for transactional emails) |
| `EmailBatch` | Batch sending | KEEP (for transactional emails) |
| `EmailLogInterceptor` | Logging | KEEP |

---

## Part 3: New In-App Messaging System Architecture

### Key Design Decisions

1. **Recipient is Person or Group** - Messages are addressed to a Person or Group (polymorphic), not directly to User. This is important because:
   - A User can have multiple Person profiles (e.g., stage name vs real name)
   - Messages should show which profile received them
   - Groups can also receive messages

2. **No separate `production` column** - Production is derived from the `regarding` object:
   - `regarding: Show` → `regarding.production`
   - `regarding: Production` → `regarding` itself
   - `regarding: AuditionCycle` → `regarding.production`
   - `regarding: SignUpForm` → `regarding.production`
   - `regarding: nil` (direct message) → use `organization` for context only

3. **Batched messages** - When sending to multiple people, a `MessageBatch` links them together (like `EmailBatch`). This enables:
   - Showing "sent to X recipients"
   - Viewing all recipients of a bulk message
   - Each recipient gets their own Message record

4. **Threaded replies** - Messages have `parent_id` for reply chains (like LinkedIn)

### New Database Tables

#### `message_batches` table
```ruby
create_table :message_batches do |t|
  t.references :sender, polymorphic: true, null: false  # User or Person who sent
  t.references :organization, foreign_key: true, null: true
  t.references :regarding, polymorphic: true, null: true
  t.string :subject, null: false
  t.integer :recipient_count, null: false, default: 0
  t.string :message_type, null: false  # cast_contact, talent_pool, direct, system
  t.timestamps

  t.index [:sender_type, :sender_id]
end
```

#### `messages` table
```ruby
create_table :messages do |t|
  # Who sent (User or Person)
  t.references :sender, polymorphic: true, null: false

  # Who receives (Person or Group - NOT User directly!)
  # The system finds the User via recipient.user
  t.references :recipient, polymorphic: true, null: false

  # Optional: link to batch if sent to multiple people
  t.references :message_batch, foreign_key: true, null: true

  # Organization context (for scoping, not derived from regarding)
  t.references :organization, foreign_key: true, null: true

  # What object this message is "regarding" (polymorphic)
  # Production is derived from this, not stored separately
  # Examples: Show, Production, AuditionCycle, SignUpForm
  t.references :regarding, polymorphic: true, null: true

  # Threading: parent message for replies
  t.references :parent, foreign_key: { to_table: :messages }, null: true

  # Content
  t.string :subject, null: false
  # Body uses ActionText (has_rich_text :body)

  # Message categorization
  t.string :message_type, null: false  # cast_contact, talent_pool, direct, system

  # Status tracking
  t.datetime :read_at
  t.datetime :archived_at
  t.timestamps

  t.index [:recipient_type, :recipient_id, :read_at]
  t.index [:recipient_type, :recipient_id, :created_at]
  t.index [:regarding_type, :regarding_id]
  t.index :parent_id
  t.index :message_batch_id
end
```

**Regarding Examples:**
| Message Type | Regarding Object | Derived Production |
|--------------|------------------|-------------------|
| Cast contact for show | `Show` | `regarding.production` |
| Talent pool message | `Production` | `regarding` (is the production) |
| Audition follow-up | `AuditionCycle` | `regarding.production` |
| Sign-up reminder | `SignUpForm` | `regarding.production` |
| Direct message | `nil` | None (use organization for context) |

#### User preferences for email digest
```ruby
# Add to users table:
add_column :users, :message_digest_enabled, :boolean, default: true
add_column :users, :last_message_digest_sent_at, :datetime, null: true
```

### Email Digest Strategy (Smart Notification Batching)

The problem: If we email for each unread message, users get spammed. If we never re-notify about old messages, they might miss important things.

**Solution: Daily digest with 1-hour delay**

1. **Trigger**: Run job hourly
2. **Check**: Does user have unread messages older than 1 hour?
3. **Throttle**: Has it been 24+ hours since last digest email?
4. **Send**: One email listing ALL unread messages (not just new ones)
5. **Track**: Update `last_message_digest_sent_at`

This means:
- You'll never get more than one email per day about unread messages
- New messages get 1 hour grace period (you might see them in-app)
- The digest shows everything unread, so you don't miss older messages
- If you read all messages, no more emails until new ones arrive

```ruby
# Pseudo-code for digest logic
class MessageDigestJob < ApplicationJob
  def perform
    User.where(message_digest_enabled: true).find_each do |user|
      # Skip if no unread messages older than 1 hour
      unread = user.unread_messages.where("messages.created_at < ?", 1.hour.ago)
      next if unread.empty?

      # Skip if already sent digest in last 24 hours
      next if user.last_message_digest_sent_at&.> 24.hours.ago

      # Send digest with ALL unread messages
      MessageDigestMailer.unread_digest(user, user.unread_messages).deliver_later
      user.update!(last_message_digest_sent_at: Time.current)
    end
  end
end
```

### New Models

#### `app/models/message_batch.rb`
```ruby
class MessageBatch < ApplicationRecord
  belongs_to :sender, polymorphic: true
  belongs_to :organization, optional: true
  belongs_to :regarding, polymorphic: true, optional: true

  has_many :messages, dependent: :nullify

  enum :message_type, {
    cast_contact: "cast_contact",
    talent_pool: "talent_pool",
    direct: "direct",
    system: "system"
  }

  validates :subject, presence: true, length: { maximum: 255 }
  validates :message_type, presence: true

  # Get all recipients (People and Groups) from associated messages
  def recipients
    messages.includes(:recipient).map(&:recipient)
  end
end
```

#### `app/models/message.rb`
```ruby
class Message < ApplicationRecord
  belongs_to :sender, polymorphic: true  # User or Person
  belongs_to :recipient, polymorphic: true  # Person or Group (NOT User!)
  belongs_to :message_batch, optional: true
  belongs_to :organization, optional: true
  belongs_to :regarding, polymorphic: true, optional: true
  belongs_to :parent, class_name: "Message", optional: true

  has_many :replies, class_name: "Message", foreign_key: :parent_id, dependent: :destroy
  has_rich_text :body

  scope :unread, -> { where(read_at: nil) }
  scope :read, -> { where.not(read_at: nil) }
  scope :active, -> { where(archived_at: nil) }
  scope :top_level, -> { where(parent_id: nil) }
  scope :for_user, ->(user) {
    # Find messages where recipient is any of user's people or groups
    person_ids = user.people.pluck(:id)
    group_ids = user.person&.groups&.pluck(:id) || []

    where(recipient_type: "Person", recipient_id: person_ids)
      .or(where(recipient_type: "Group", recipient_id: group_ids))
  }

  enum :message_type, {
    cast_contact: "cast_contact",    # Manager → cast about a show
    talent_pool: "talent_pool",      # Manager → talent pool members
    direct: "direct",                # Person → person
    system: "system"                 # System notifications
  }

  validates :subject, presence: true, length: { maximum: 255 }
  validates :message_type, presence: true

  def mark_as_read!
    update!(read_at: Time.current) if read_at.nil?
  end

  def unread?
    read_at.nil?
  end

  def reply?
    parent_id.present?
  end

  # Get the User who should see this message
  def recipient_user
    case recipient
    when Person then recipient.user
    when Group then recipient.members.first&.user  # Groups need special handling
    end
  end

  # Human-readable sender name
  def sender_name
    case sender
    when User then sender.person&.name || sender.email_address
    when Person then sender.name
    else "CocoScout"
    end
  end

  # Human-readable recipient name (shows which profile received it)
  def recipient_name
    case recipient
    when Person then recipient.name
    when Group then recipient.name
    else "Unknown"
    end
  end

  # Derive production from regarding object (no separate production column)
  def production
    case regarding
    when Show then regarding.production
    when Production then regarding
    when AuditionCycle then regarding.production
    when SignUpForm then regarding.production
    else nil
    end
  end

  # Context card info based on regarding object
  def regarding_context
    return nil unless regarding

    case regarding
    when Show
      {
        type: :show,
        title: regarding.production.name,
        subtitle: regarding.formatted_date_and_time,
        location: regarding.display_location,
        image: regarding.production.posters.primary.first&.safe_image_variant(:small)
      }
    when Production
      {
        type: :production,
        title: regarding.name,
        image: regarding.logo
      }
    when AuditionCycle
      {
        type: :audition,
        title: regarding.production.name,
        subtitle: "Auditions: #{regarding.name}"
      }
    when SignUpForm
      {
        type: :signup,
        title: regarding.name,
        subtitle: regarding.production.name
      }
    else
      nil
    end
  end
end
```

### User Model Additions

Add to `app/models/user.rb`:
```ruby
# Messaging - messages addressed to any of user's People or Groups
def received_messages
  Message.for_user(self)
end

def unread_messages
  received_messages.unread.active
end

def unread_message_count
  unread_messages.count
end
```

### Person Model Additions

Add to `app/models/person.rb`:
```ruby
# Messages addressed to this person
has_many :received_messages, as: :recipient, class_name: "Message", dependent: :destroy
has_many :sent_messages, as: :sender, class_name: "Message", dependent: :nullify
```

### Group Model Additions

Add to `app/models/group.rb`:
```ruby
# Messages addressed to this group
has_many :received_messages, as: :recipient, class_name: "Message", dependent: :destroy
```

### New Controllers

#### `app/controllers/my/inbox_controller.rb`
```ruby
class My::InboxController < ApplicationController
  before_action :require_authentication
  before_action :set_sidebar

  def index
    @show_my_sidebar = true
    @messages = current_user.received_messages
                            .top_level
                            .active
                            .includes(:sender, :recipient, :regarding, :message_batch)
                            .order(created_at: :desc)
    @pagy, @messages = pagy(@messages, items: 25)
    @unread_count = current_user.unread_message_count
  end

  def show
    @show_my_sidebar = true
    @message = current_user.received_messages.find(params[:id])
    @message.mark_as_read!

    # Load replies (threaded)
    @replies = @message.replies.includes(:sender, :recipient).order(:created_at)

    # If part of a batch, show recipient count
    @batch = @message.message_batch
  end

  def archive
    @message = current_user.received_messages.find(params[:id])
    @message.update!(archived_at: Time.current)

    respond_to do |format|
      format.html { redirect_to my_inbox_index_path, notice: "Message archived" }
      format.turbo_stream
    end
  end

  def mark_read
    @message = current_user.received_messages.find(params[:id])
    @message.mark_as_read!

    respond_to do |format|
      format.html { redirect_to my_inbox_index_path }
      format.turbo_stream
    end
  end

  def mark_all_read
    current_user.unread_messages.update_all(read_at: Time.current)
    redirect_to my_inbox_index_path, notice: "All messages marked as read"
  end

  # POST /my/inbox/:id/reply
  def reply
    parent = current_user.received_messages.find(params[:id])

    @reply = Message.create!(
      sender: current_user.person,
      recipient: parent.sender,  # Reply goes back to sender
      parent: parent,
      organization: parent.organization,
      regarding: parent.regarding,
      subject: "Re: #{parent.subject}",
      body: params[:body],
      message_type: :direct
    )

    respond_to do |format|
      format.html { redirect_to my_inbox_path(parent), notice: "Reply sent" }
      format.turbo_stream
    end
  end

  private

  def set_sidebar
    @show_my_sidebar = true
  end
end
```

#### Update `app/controllers/manage/productions_controller.rb`
Replace email-based cast contact with message creation.

### New Views

| File | Purpose |
|------|---------|
| `app/views/my/inbox/index.html.erb` | Message list |
| `app/views/my/inbox/show.html.erb` | Single message view |
| `app/views/shared/_message_badge.html.erb` | Unread count badge for nav |
| `app/views/shared/_message_compose_modal.html.erb` | Unified compose modal |
| `app/views/shared/_regarding_context_card.html.erb` | Context card for regarding object |

### Unified Compose Modal

A single Stimulus controller and modal that can be used anywhere to compose messages.
Uses CocoScout styling: pink accents, rounded-lg corners, standard button partial.

```erb
<%# app/views/shared/_message_compose_modal.html.erb %>
<%#
  Usage:
  <%= render "shared/message_compose_modal",
    recipients: @people,           # Array of People (not Users!)
    regarding: @show,              # Optional: object to attach as context
    subject_prefix: "[Show Name]", # Optional: prepend to subject
    message_type: "cast_contact",  # Required: cast_contact, talent_pool, direct
    organization: @organization    # For scoping
  %>
%>

<div data-controller="message-compose"
     data-message-compose-regarding-type-value="<%= regarding&.class&.name %>"
     data-message-compose-regarding-id-value="<%= regarding&.id %>"
     class="hidden fixed inset-0 z-50" id="message-compose-modal">
  <div class="fixed inset-0 bg-black/50" data-action="click->message-compose#close"></div>

  <div class="fixed inset-x-4 top-1/2 -translate-y-1/2 max-w-2xl mx-auto bg-white rounded-lg shadow-xl overflow-hidden">
    <%# Header %>
    <div class="flex items-center justify-between px-6 py-4 border-b border-gray-200">
      <h3 class="text-lg font-semibold text-gray-900">Send Message</h3>
      <button type="button" data-action="message-compose#close" class="text-gray-400 hover:text-gray-600">
        <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
        </svg>
      </button>
    </div>

    <%# Regarding context card (if present) %>
    <% if regarding.present? %>
      <%= render "shared/regarding_context_card", regarding: regarding %>
    <% end %>

    <%# Form %>
    <%= form_with url: send_path, method: :post, data: { message_compose_target: "form" } do |f| %>
      <%= hidden_field_tag :regarding_type, regarding&.class&.name %>
      <%= hidden_field_tag :regarding_id, regarding&.id %>
      <%= hidden_field_tag :message_type, message_type %>

      <div class="px-6 py-4 space-y-4">
        <%# Recipients %>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">To</label>
          <div class="flex flex-wrap gap-2 p-2 border border-gray-300 rounded-lg min-h-[40px]">
            <% recipients.each do |person| %>
              <span class="inline-flex items-center gap-1 px-2 py-1 bg-pink-100 text-pink-800 text-sm rounded-full">
                <%= person.name %>
                <%= hidden_field_tag "person_ids[]", person.id %>
              </span>
            <% end %>
          </div>
          <p class="mt-1 text-xs text-gray-500"><%= recipients.size %> recipient(s)</p>
        </div>

        <%# Subject %>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Subject</label>
          <%= f.text_field :subject,
              value: subject_prefix,
              class: "w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-pink-500 focus:border-pink-500",
              placeholder: "Enter subject..." %>
        </div>

        <%# Body %>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Message</label>
          <%= f.rich_text_area :body, class: "w-full" %>
        </div>
      </div>

      <%# Footer %>
      <div class="flex items-center justify-end gap-3 px-6 py-4 bg-gray-50 border-t border-gray-200">
        <button type="button" data-action="message-compose#close"
                class="px-4 py-2 text-gray-700 hover:text-gray-900">
          Cancel
        </button>
        <%= render "shared/button", text: "Send Message", variant: "primary", size: "medium", type: :submit %>
      </div>
    <% end %>
  </div>
</div>
```

The modal is triggered from various places:
- Show detail page → "Contact Cast" button → `regarding: @show`
- Talent pool page → "Send Message" button → `regarding: @production`
- Person profile → "Send Message" button → `regarding: nil` (direct)

### Regarding Context Card

When viewing a message, if it has a `regarding` object, display a context card:

```erb
<%# app/views/shared/_regarding_context_card.html.erb %>
<% if message.regarding.present? %>
  <% context = message.regarding_context %>
  <div class="flex items-center gap-3 p-3 bg-gray-50 rounded-lg border border-gray-200 mb-4">
    <% if context[:image] %>
      <%= image_tag context[:image], class: "w-12 h-12 rounded-lg object-cover" %>
    <% else %>
      <div class="w-12 h-12 rounded-lg bg-pink-100 flex items-center justify-center">
        <!-- Icon based on context[:type] -->
      </div>
    <% end %>
    <div>
      <p class="font-medium text-gray-900"><%= context[:title] %></p>
      <% if context[:subtitle] %>
        <p class="text-sm text-gray-500"><%= context[:subtitle] %></p>
      <% end %>
      <% if context[:location] %>
        <p class="text-xs text-gray-400"><%= context[:location] %></p>
      <% end %>
    </div>
  </div>
<% end %>
```

### Message List Item

Shows sender headshot, subject, regarding context preview, and unread indicator.
**Important**: Uses pink for unread indicators and badges to match CocoScout styling.

```erb
<%# app/views/my/inbox/_message_row.html.erb %>
<%= link_to my_inbox_path(message), class: "block hover:bg-gray-50 transition-colors" do %>
  <div class="flex items-start gap-3 p-4 <%= message.unread? ? 'bg-pink-50 border-l-4 border-pink-500' : 'bg-white' %> border-b border-gray-200">
    <%# Sender headshot %>
    <% sender_person = message.sender.is_a?(Person) ? message.sender : message.sender.person %>
    <% if sender_person %>
      <% headshot_variant = sender_person.safe_headshot_variant(:thumb) %>
      <% if headshot_variant %>
        <%= image_tag headshot_variant, alt: sender_person.name, class: "w-10 h-10 rounded-lg object-cover flex-shrink-0" %>
      <% else %>
        <div class="w-10 h-10 rounded-lg bg-gray-200 flex items-center justify-center text-gray-600 font-bold text-sm flex-shrink-0">
          <%= sender_person.initials %>
        </div>
      <% end %>
    <% else %>
      <div class="w-10 h-10 rounded-lg bg-pink-100 flex items-center justify-center flex-shrink-0">
        <svg class="w-5 h-5 text-pink-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"/>
        </svg>
      </div>
    <% end %>

    <div class="flex-1 min-w-0">
      <div class="flex items-center gap-2 flex-wrap">
        <span class="font-medium text-gray-900"><%= message.sender_name %></span>
        <% if message.regarding.present? %>
          <span class="text-xs text-pink-700 bg-pink-100 px-2 py-0.5 rounded-full">
            <%= message.regarding_context[:title].truncate(25) %>
          </span>
        <% end %>
        <% if message.message_batch.present? %>
          <span class="text-xs text-gray-500 bg-gray-100 px-2 py-0.5 rounded-full">
            +<%= message.message_batch.recipient_count - 1 %> others
          </span>
        <% end %>
      </div>
      <p class="text-gray-900 truncate"><%= message.subject %></p>
      <p class="text-sm text-gray-500"><%= time_ago_in_words(message.created_at) %> ago</p>
    </div>

    <% if message.unread? %>
      <span class="w-3 h-3 bg-pink-500 rounded-full flex-shrink-0 mt-1"></span>
    <% end %>
  </div>
<% end %>
```

### Unread Badge (Navigation)

Pink badge for unread count in sidebar/nav:

```erb
<%# app/views/shared/_message_badge.html.erb %>
<% count = current_user&.unread_message_count || 0 %>
<% if count > 0 %>
  <span class="inline-flex items-center justify-center min-w-[20px] h-5 px-1.5 text-xs font-bold text-white bg-pink-500 rounded-full">
    <%= count > 99 ? "99+" : count %>
  </span>
<% end %>
```

### New Background Job

#### `app/jobs/message_digest_job.rb`

Smart digest logic:
- Runs hourly
- Checks if user has unread messages older than 1 hour
- Only sends if 24+ hours since last digest
- Includes ALL unread messages (not just new ones)

```ruby
class MessageDigestJob < ApplicationJob
  queue_as :default

  # Run this hourly via cron/recurring job
  def perform
    User.where(message_digest_enabled: true).find_each do |user|
      process_user(user)
    end
  end

  private

  def process_user(user)
    # Get unread messages older than 1 hour (grace period for in-app viewing)
    unread_messages = user.unread_messages
                          .where("messages.created_at < ?", 1.hour.ago)
                          .includes(:sender, :recipient, :regarding)
                          .order(created_at: :desc)

    # Skip if no unread messages (or all are within grace period)
    return if unread_messages.empty?

    # Skip if already sent digest in last 24 hours
    return if user.last_message_digest_sent_at&.> 24.hours.ago

    # Send digest with ALL unread messages
    MessageDigestMailer.unread_digest(
      user: user,
      messages: unread_messages.to_a
    ).deliver_later

    # Update timestamp to prevent spam
    user.update!(last_message_digest_sent_at: Time.current)
  end
end
```

### New Mailer (Digest-Based)

#### `app/mailers/message_digest_mailer.rb`
```ruby
class MessageDigestMailer < ApplicationMailer
  def unread_digest(user:, messages:)
    @user = user
    @messages = messages
    @message_count = messages.size

    # Use EmailTemplate for the body
    template = EmailTemplate.find_by(slug: "message_digest")
    @rendered_body = EmailTemplateService.render_body(
      "message_digest",
      {
        user_name: @user.person&.name || "there",
        message_count: @message_count,
        messages_summary: build_messages_summary(@messages),
        inbox_url: my_inbox_index_url
      }
    )

    mail(
      to: @user.email_address,
      subject: "You have #{@message_count} unread #{'message'.pluralize(@message_count)} on CocoScout"
    )
  end

  private

  def build_messages_summary(messages)
    # Build HTML list of messages (just sender + subject, no body content)
    messages.first(5).map do |msg|
      "<li><strong>#{msg.sender_name}</strong>: #{msg.subject}</li>"
    end.join("\n")
  end
end
```

#### Email Template (created via migration)

```ruby
# db/migrate/xxx_create_message_digest_email_template.rb
class CreateMessageDigestEmailTemplate < ActiveRecord::Migration[7.1]
  def up
    EmailTemplate.create!(
      slug: "message_digest",
      name: "Message Digest",
      subject: "You have {{message_count}} unread messages on CocoScout",
      body: <<~HTML
        <p>Hi {{user_name}},</p>

        <p>You have <strong>{{message_count}} unread message(s)</strong> waiting for you on CocoScout:</p>

        <ul>
          {{messages_summary}}
        </ul>

        <p><a href="{{inbox_url}}" style="display: inline-block; background-color: #ec4899; color: white; padding: 12px 24px; text-decoration: none; border-radius: 8px; font-weight: 600;">View Your Inbox</a></p>

        <p style="color: #6b7280; font-size: 14px;">
          You're receiving this because you have message notifications enabled.
          You can adjust your notification preferences in your account settings.
        </p>
      HTML
    )
  end

  def down
    EmailTemplate.find_by(slug: "message_digest")&.destroy
  end
end
```

**Important**: The digest email does NOT include message body content, just:
- Sender name
- Subject line
- Link to inbox

This encourages users to visit the app and protects privacy.

### New Routes

```ruby
# config/routes.rb
namespace :my do
  resources :inbox, only: [:index, :show] do
    member do
      post :archive
      post :mark_read
      post :reply
    end
    collection do
      post :mark_all_read
    end
  end
end

# Manage namespace - add message sending endpoints
namespace :manage do
  # Add to shows controller
  scope "/shows/:production_id" do
    post ":id/contact_cast", to: "shows#contact_cast", as: :contact_cast_show
  end

  # Add to talent_pools controller
  scope "/talent_pools/:production_id" do
    post "message", to: "talent_pools#send_message", as: :message_talent_pool
  end
end
```

### Navigation Updates

Add unread message badge to:
- Main navigation (My CocoScout dropdown)
- Mobile menu
- Dashboard

### Consolidated Service Object for Sending Messages

#### `app/services/message_service.rb`

All message sending goes through this single service. It handles:
- Creating MessageBatch for bulk sends
- Creating individual Messages for each recipient (Person or Group)
- Attaching the "regarding" object for context
- Setting the correct message type

**Key change**: Recipients are now **Person or Group**, not User. The system delivers to the User via `person.user`.

```ruby
class MessageService
  class << self
    # Send to cast of a specific show
    # Recipients are People assigned to the show
    def send_to_show_cast(show:, sender:, subject:, body:)
      # Get People (not Users) who are cast in this show
      people = show.role_assignments.includes(:entity).map do |ra|
        ra.entity.is_a?(Person) ? ra.entity : ra.entity.members
      end.flatten.uniq

      send_to_people(
        sender: sender,
        people: people,
        subject: subject,
        body: body,
        organization: show.production.organization,
        regarding: show,
        message_type: :cast_contact
      )
    end

    # Send to all cast of a production (all shows)
    def send_to_production_cast(production:, sender:, subject:, body:)
      people = production.cast_people.to_a

      send_to_people(
        sender: sender,
        people: people,
        subject: subject,
        body: body,
        organization: production.organization,
        regarding: production,
        message_type: :cast_contact
      )
    end

    # Send to talent pool members
    def send_to_talent_pool(production:, sender:, subject:, body:, person_ids: nil)
      pool = production.effective_talent_pool
      people = person_ids ? pool.people.where(id: person_ids).to_a : pool.people.to_a

      send_to_people(
        sender: sender,
        people: people,
        subject: subject,
        body: body,
        organization: production.organization,
        regarding: production,
        message_type: :talent_pool
      )
    end

    # Send direct message to a specific Person
    # No "regarding" object - just a direct conversation
    def send_direct(sender:, recipient_person:, subject:, body:, organization: nil)
      Message.create!(
        sender: sender,
        recipient: recipient_person,  # Person, not User!
        organization: organization,
        subject: subject,
        body: body,
        message_type: :direct
      )
    end

    # Send to a Group (all members receive individually, but message shows group context)
    def send_to_group(sender:, group:, subject:, body:, organization: nil, regarding: nil)
      send_to_people(
        sender: sender,
        people: group.members.to_a,
        subject: subject,
        body: body,
        organization: organization || group.production&.organization,
        regarding: regarding,
        message_type: :cast_contact
      )
    end

    private

    # Core method: send to array of People, creating a batch if multiple
    def send_to_people(sender:, people:, subject:, body:, message_type:,
                       organization: nil, regarding: nil)
      people = people.uniq.select { |p| p.user.present? }  # Only people with accounts
      return [] if people.empty?

      # Create batch if sending to multiple people
      batch = nil
      if people.size > 1
        batch = MessageBatch.create!(
          sender: sender,
          organization: organization,
          regarding: regarding,
          subject: subject,
          message_type: message_type,
          recipient_count: people.size
        )
      end

      # Create individual message for each person
      messages = people.map do |person|
        Message.create!(
          sender: sender,
          recipient: person,  # Person, not User!
          message_batch: batch,
          organization: organization,
          regarding: regarding,
          subject: subject,
          body: body,
          message_type: message_type
        )
      end

      messages
    end
  end
end
```

**Usage Examples:**

```ruby
# Manager contacts cast about upcoming show
# Each Person in the cast gets their own message, linked by MessageBatch
MessageService.send_to_show_cast(
  show: @show,
  sender: Current.user,
  subject: "Reminder: Call time is 6pm",
  body: "Please arrive by 6pm for warmups..."
)

# Manager sends to talent pool about auditions
MessageService.send_to_talent_pool(
  production: @production,
  sender: Current.user,
  subject: "New audition opportunity!",
  body: "We're casting for our spring show..."
)

# Direct message to a specific Person (not User!)
# This is important when a user has multiple profiles
MessageService.send_direct(
  sender: Current.user.person,
  recipient_person: @person,  # The specific Person profile to message
  subject: "Question about your availability",
  body: "Hey, I noticed you're marked as unavailable..."
)

# View batch recipients (for "sent to X people" display)
batch = message.message_batch
if batch
  puts "Sent to #{batch.recipient_count} people"
  batch.messages.each { |m| puts "  - #{m.recipient_name}" }
end
```

---

## Part 4: Implementation Order

### Phase 1: Database Setup
1. Create migration to add `messages` table
2. Create migration to add message preferences to `users`
3. Create Message model with validations and scopes

### Phase 2: Core Messaging
1. Create `My::InboxController`
2. Create inbox views (list, show)
3. Add routes
4. Add unread badge to navigation

### Phase 3: Background Email Reminders
1. Create `MessageEmailReminderJob`
2. Create `MessageReminderMailer` with minimal template
3. Schedule job to run hourly via cron/Sidekiq

### Phase 4: Convert Existing Email Points
1. Replace `Manage::ProductionMailer#contact_cast` → `MessageService.send_to_cast`
2. Replace `Manage::PersonMailer#contact` → `MessageService.send_direct`
3. Replace talent pool messages → `MessageService.send_direct`
4. Update all UI forms that send these emails

### Phase 5: Remove Forum Infrastructure
1. Drop `posts` and `post_views` tables
2. Remove forum fields from Organization/Production (forum_mode, forum_enabled, shared_forum_name)
3. Clean up associations

### Phase 6: Move Questionnaires to Casting
1. Update routes: `/manage/communications/:prod/questionnaires` → `/manage/casting/:prod/questionnaires`
2. Update all `_path` helpers in questionnaire views
3. Update breadcrumbs to reference Casting module
4. Add Questionnaires action to Casting module header

### Phase 7: Remove User-Facing Email Views
1. Delete `My::MessagesController` entirely
2. Delete `Manage::CommunicationsController` entirely
3. Delete `Manage::OrgCommunicationsController` entirely
4. Delete all associated views directories
5. Remove all communications routes (questionnaires already moved)

### Phase 8: Remove Old Email Infrastructure
1. Delete `Manage::ProductionMailer#send_message` method
2. Delete `CommunicationsMailer` entirely
3. Delete `My::TalentMessageMailer` entirely
4. Delete associated email templates

---

## Part 5: Files to Create

### Database Migrations
| File | Purpose |
|------|---------|
| `db/migrate/xxx_create_message_batches.rb` | MessageBatch table for bulk sends |
| `db/migrate/xxx_create_messages.rb` | Messages table with polymorphic recipient, regarding, parent |
| `db/migrate/xxx_add_message_digest_to_users.rb` | User digest preferences (enabled, last_sent_at) |
| `db/migrate/xxx_create_message_digest_email_template.rb` | EmailTemplate for digest emails |
| `db/migrate/xxx_drop_forum_tables.rb` | Remove posts, post_views, forum fields |

### Models
| File | Purpose |
|------|---------|
| `app/models/message_batch.rb` | Links messages sent to multiple recipients |
| `app/models/message.rb` | Message model with polymorphic recipient (Person/Group) |

### Controllers
| File | Purpose |
|------|---------|
| `app/controllers/my/inbox_controller.rb` | Inbox (list, show, archive, mark_read) |

### Views - Inbox (New)
| File | Purpose |
|------|---------|
| `app/views/my/inbox/index.html.erb` | Message list with pink unread indicators |
| `app/views/my/inbox/show.html.erb` | Message detail with regarding card + reply form |
| `app/views/my/inbox/_message_row.html.erb` | Single message row (partial) |
| `app/views/my/inbox/_reply.html.erb` | Threaded reply display |
| `app/views/my/inbox/_reply_form.html.erb` | Form to post reply |
| `app/views/my/inbox/archive.turbo_stream.erb` | Turbo stream for archive action |
| `app/views/my/inbox/mark_read.turbo_stream.erb` | Turbo stream for mark read |

### Views - Shared Components (New)
| File | Purpose |
|------|---------|
| `app/views/shared/_message_badge.html.erb` | Unread count badge for navigation |
| `app/views/shared/_message_compose_modal.html.erb` | Unified compose modal (Stimulus) |
| `app/views/shared/_regarding_context_card.html.erb` | Context card for regarding object |

### Views to Modify (Add "Send Message" buttons)
| File | Change |
|------|--------|
| `app/views/manage/shows/show.html.erb` | Add "Contact Cast" button |
| `app/views/manage/talent_pools/index.html.erb` | Add "Message Pool" button |
| `app/views/shared/_person_modal.html.erb` (if exists) | Add "Send Message" button |
| `app/views/layouts/_my_sidebar.html.erb` | Replace Messages with Inbox |
| `app/views/layouts/_manage_sidebar.html.erb` | Remove Communications link |

### Views to Modify (Move Questionnaires to Casting)
| File | Change |
|------|--------|
| `app/views/manage/questionnaires/*.html.erb` | Update breadcrumbs to reference Casting |
| `app/views/manage/casting/index.html.erb` | Add Questionnaires to module header actions |
| All questionnaire views | Update `_path` helpers from `communications_` to `casting_` |

### Services
| File | Purpose |
|------|---------|
| `app/services/message_service.rb` | Unified message sending (replaces 3 mailers) |

### Background Jobs
| File | Purpose |
|------|---------|
| `app/jobs/message_digest_job.rb` | Sends daily digest for unread messages (smart batching) |

### Mailers
| File | Purpose |
|------|---------|
| `app/mailers/message_digest_mailer.rb` | "You have X unread messages" digest email |
| `app/views/message_digest_mailer/unread_digest.html.erb` | Digest email template (uses EmailTemplate) |
| `app/views/message_digest_mailer/unread_digest.text.erb` | Plain text version |

### Stimulus Controllers
| File | Purpose |
|------|---------|
| `app/javascript/controllers/message_compose_controller.js` | Compose modal (open/close, form handling) |
| `app/javascript/controllers/message_inbox_controller.js` | Inbox list (batch select, mark read) |

## Part 6: Files to Delete

### Forum System (Complete Removal)

**Models:**
- `app/models/post.rb`
- `app/models/post_view.rb`

### User-Facing Email/Message Views (Complete Removal)

**Controllers:**
- `app/controllers/my/messages_controller.rb`
- `app/controllers/manage/communications_controller.rb`
- `app/controllers/manage/org_communications_controller.rb`

**Views:**
- `app/views/my/messages/` (entire directory)
- `app/views/manage/communications/` (entire directory)
- `app/views/manage/org_communications/` (entire directory)

### Controllers to DELETE

These controllers are deleted entirely (replaced by new inbox + MessageService):

| File | Why Delete |
|------|------------|
| `app/controllers/my/messages_controller.rb` | Forum + email viewing - both removed |
| `app/controllers/manage/communications_controller.rb` | Email viewing + send - both removed |
| `app/controllers/manage/org_communications_controller.rb` | Email viewing + send - both removed |

### Mailers to Delete (replaced by MessageService)

After in-app messaging is verified working, delete these mailer methods:

**Mailer files/methods to remove:**
- `app/mailers/manage/production_mailer.rb` → remove `send_message` method
- `app/mailers/communications_mailer.rb` → delete entire file (only has `send_message`)
- `app/mailers/my/talent_message_mailer.rb` → delete entire file

**Email templates to delete:**
- `app/views/manage/production_mailer/send_message.html.erb`
- `app/views/communications_mailer/` → delete entire directory
- `app/views/my/talent_message_mailer/send_to_production.html.erb`
- `app/views/my/talent_message_mailer/send_to_production.text.erb`

---

## Part 7: Navigation Changes

### My CocoScout Sidebar

Current "Messages" entry in sidebar:
- **Remove**: "Messages" link (forum) entirely
- **Add**: "Inbox" link with unread count badge

### Manage Navigation

- **Remove**: "Communications" link from org sidebar (email log viewer is gone)
- **Move Questionnaires**: From `/manage/communications/:production_id/questionnaires` to Casting module

### Questionnaires Relocation

Questionnaires move from Communications to Casting:

**New URL structure:**
- `/manage/casting/:production_id/questionnaires` (list)
- `/manage/casting/:production_id/questionnaires/new` (new)
- `/manage/casting/:production_id/questionnaires/:id` (show)
- etc.

**Casting Module Header** (add as 4th action):
```erb
actions: [
  { icon: "clipboard-list", text: "Casting Table", path: casting_table_path },
  { icon: "user-group", text: "Talent Pool", path: talent_pool_path },
  { icon: "calendar", text: "Availability", path: availability_path },
  { icon: "document-text", text: "Questionnaires", path: questionnaires_path }  # NEW
]
```

**Breadcrumbs** for questionnaire pages:
```erb
breadcrumbs: [
  ["Casting", manage_casting_production_path(@production)],
  ["Questionnaires", manage_casting_questionnaires_path(@production)]
],
text: "New Questionnaire"
```

### Where "Send Message" Buttons Move To

Since we're removing the Communications pages, add "Send Message" buttons to:

| Location | Button | Opens Modal With |
|----------|--------|------------------|
| Show detail page (`/manage/shows/:prod/:id`) | "Contact Cast" | `regarding: @show`, recipients: cast members |
| Talent pool page (`/manage/talent_pools/:prod`) | "Message Pool" | `regarding: @production`, recipients: pool members |
| Person modal (anywhere) | "Send Message" | `regarding: nil`, recipient: person |
| Production settings? | "Message All Cast" | `regarding: @production`, recipients: all cast |

---

## Approval Checklist

Please confirm each design decision:

### Data Model
- [ ] **Recipient is Person or Group** (not User): Messages are addressed to a specific Person profile or Group, not the User directly. This allows users with multiple profiles to see which profile received the message.
- [ ] **No separate `production` column**: Production is derived from `regarding` object (Show→production, Production→itself, AuditionCycle→production, etc.)
- [ ] **MessageBatch for bulk sends**: When sending to multiple people, a `MessageBatch` links the individual messages together (like EmailBatch)
- [ ] **Threading with `parent_id`**: Messages have a parent reference for threaded replies (like LinkedIn)

### Forum Removal
- [ ] **Delete forum completely**: Post/PostView models, forum views, forum_mode/forum_enabled fields, all forum routes

### Email History Removal
- [ ] **Delete user-facing email viewing**:
  - `/my/messages/emails` and `/my/messages/:id` - user's received emails
  - `/manage/communications` - production email logs
  - `/manage/org_communications` - org email logs
  - (Superadmin email monitor stays)

### MessageService API
- [ ] **Unified service** replaces all "send message" email functions:
  - `MessageService.send_to_show_cast(show:, sender:, ...)` - recipients are People in cast
  - `MessageService.send_to_production_cast(production:, sender:, ...)` - recipients are cast People
  - `MessageService.send_to_talent_pool(production:, sender:, ...)` - recipients are talent pool People
  - `MessageService.send_direct(sender:, recipient_person:, ...)` - single Person recipient

### Email Digest Strategy
- [ ] **Smart daily digest** (not per-message emails):
  - Job runs hourly
  - 1-hour grace period for new messages (user might see them in-app)
  - Max 1 digest email per 24 hours per user
  - Digest includes ALL unread messages, not just new ones
  - Does NOT include message body content, just sender + subject + link

### Delete These Mailers
- [ ] `Manage::ProductionMailer#send_message`
- [ ] `CommunicationsMailer` (entire file)
- [ ] `My::TalentMessageMailer` (entire file)

### Keep Transactional Emails
- [ ] Auth, casting decisions, show cancellation, vacancy, ticket, reminder emails stay as direct emails

### New UI
- [ ] **Inbox at `/my/inbox`** with pink unread badges
- [ ] **Regarding context card** shows related object (Show poster, Production logo, etc.)
- [ ] **Reply threading** in message detail view

### Navigation Changes
- [ ] **Move Questionnaires**: From `/manage/communications/` to `/manage/casting/`
- [ ] **Replace "Messages" with "Inbox"** in My sidebar (with pink unread badge)
- [ ] **Remove "Communications"** from Manage navigation

### Styling
- [ ] **Pink badges** for unread counts (bg-pink-500)
- [ ] **Pink left border** on unread message rows
- [ ] **Pink accent colors** on context tags
- [ ] **Use `rounded-lg` headshots** per CLAUDE.md guidelines

Once you confirm these, I'll implement in the phased order above.
