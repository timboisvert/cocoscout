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

### New Database Tables

#### `messages` table
```ruby
create_table :messages do |t|
  # Who sent and receives
  t.references :sender, polymorphic: true, null: false  # User, Person, or System
  t.references :recipient, foreign_key: { to_table: :users }, null: false

  # Context - which org/production this relates to
  t.references :organization, foreign_key: true, null: true
  t.references :production, foreign_key: true, null: true

  # What object this message is "regarding" (polymorphic)
  # Examples: Show (cast contact), Production (talent pool msg), AuditionCycle, SignUpForm
  t.references :regarding, polymorphic: true, null: true

  # Content
  t.string :subject, null: false
  # Body uses ActionText (has_rich_text :body)

  # Message categorization
  t.string :message_type, null: false  # cast_contact, talent_pool, direct, system

  # Status tracking
  t.datetime :read_at
  t.datetime :email_reminder_sent_at
  t.datetime :archived_at
  t.timestamps

  t.index [:recipient_id, :read_at]
  t.index [:recipient_id, :created_at]
  t.index [:regarding_type, :regarding_id]
end
```

**Regarding Examples:**
| Message Type | Regarding Object | Display in Message |
|--------------|------------------|-------------------|
| Cast contact for show | `Show` | Show poster, date, time, location |
| Talent pool message | `Production` | Production logo, name |
| Audition follow-up | `AuditionCycle` | Audition name, deadline |
| Sign-up reminder | `SignUpForm` | Event name, date |
| Direct message | `nil` | No context card |

#### `message_preferences` (or add to User)
```ruby
# Add to users table:
add_column :users, :message_email_delay_hours, :integer, default: 24
add_column :users, :message_email_enabled, :boolean, default: true
```

### New Models

#### `app/models/message.rb`
```ruby
class Message < ApplicationRecord
  belongs_to :sender, polymorphic: true
  belongs_to :recipient, class_name: "User"
  belongs_to :organization, optional: true
  belongs_to :production, optional: true
  belongs_to :regarding, polymorphic: true, optional: true

  has_rich_text :body

  scope :unread, -> { where(read_at: nil) }
  scope :read, -> { where.not(read_at: nil) }
  scope :active, -> { where(archived_at: nil) }
  scope :needing_email_reminder, -> {
    unread
      .where(email_reminder_sent_at: nil)
      .where("created_at < ?", 24.hours.ago)
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

  # Human-readable sender name
  def sender_name
    case sender
    when User then sender.person&.name || sender.email_address
    when Person then sender.name
    else "CocoScout"
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
# Messaging
has_many :received_messages, class_name: "Message", foreign_key: :recipient_id, dependent: :destroy

def unread_message_count
  received_messages.unread.active.count
end
```

### New Controllers

#### `app/controllers/my/inbox_controller.rb`
```ruby
class My::InboxController < My::BaseController
  def index
    @messages = current_user.received_messages
                            .active
                            .includes(:sender)
                            .order(created_at: :desc)
                            .page(params[:page])
    @unread_count = current_user.received_messages.unread.count
  end

  def show
    @message = current_user.received_messages.find(params[:id])
    @message.mark_as_read!
  end

  def archive
    @message = current_user.received_messages.find(params[:id])
    @message.update!(archived_at: Time.current)
    redirect_to my_inbox_path, notice: "Message archived"
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

A single Stimulus controller and modal that can be used anywhere to compose messages:

```erb
<%# app/views/shared/_message_compose_modal.html.erb %>
<%#
  Usage:
  <%= render "shared/message_compose_modal",
    recipients: @people,           # Array of people or users
    regarding: @show,              # Optional: object to attach
    subject_prefix: "[Show Name]", # Optional: prepend to subject
    message_type: "cast_contact"   # Required: message type
  %>
%>
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

Shows sender, subject, regarding context preview, and unread indicator:

```erb
<%# In inbox/index.html.erb %>
<div class="flex items-start gap-3 p-4 <%= message.unread? ? 'bg-pink-50' : 'bg-white' %> border-b">
  <!-- Sender avatar -->
  <div class="flex-1">
    <div class="flex items-center gap-2">
      <span class="font-medium"><%= message.sender_name %></span>
      <% if message.regarding.present? %>
        <span class="text-xs text-gray-500 bg-gray-100 px-2 py-0.5 rounded">
          re: <%= message.regarding_context[:title].truncate(20) %>
        </span>
      <% end %>
    </div>
    <p class="text-gray-900"><%= message.subject %></p>
    <p class="text-sm text-gray-500"><%= time_ago_in_words(message.created_at) %> ago</p>
  </div>
  <% if message.unread? %>
    <span class="w-2 h-2 bg-pink-500 rounded-full"></span>
  <% end %>
</div>
```

### New Background Job

#### `app/jobs/message_email_reminder_job.rb`
```ruby
class MessageEmailReminderJob < ApplicationJob
  queue_as :default

  def perform
    Message.needing_email_reminder.find_each do |message|
      next unless message.recipient.message_email_enabled?

      delay_hours = message.recipient.message_email_delay_hours || 24
      next if message.created_at > delay_hours.hours.ago

      MessageReminderMailer.unread_message(message).deliver_later
      message.update!(email_reminder_sent_at: Time.current)
    end
  end
end
```

### New Mailer (Minimal)

#### `app/mailers/message_reminder_mailer.rb`
```ruby
class MessageReminderMailer < ApplicationMailer
  def unread_message(message)
    @message = message
    @user = message.recipient

    mail(
      to: @user.email,
      subject: "You have an unread message on CocoScout"
    )
  end
end
```

Template should NOT include message content, just:
- "You have a new message from [Sender Name]"
- "Log in to read it: [Link]"

### New Routes

```ruby
# config/routes.rb
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

### Navigation Updates

Add unread message badge to:
- Main navigation (My CocoScout dropdown)
- Mobile menu
- Dashboard

### Consolidated Service Object for Sending Messages

#### `app/services/message_service.rb`

All message sending goes through this single service. It handles:
- Creating messages for one or multiple recipients
- Attaching the "regarding" object for context
- Setting the correct message type

```ruby
class MessageService
  class << self
    # Send to cast of a specific show
    # Attaches the Show as the "regarding" object
    def send_to_show_cast(show:, sender:, subject:, body:)
      recipients = show.cast_users
      send_bulk(
        sender: sender,
        recipients: recipients,
        subject: subject,
        body: body,
        organization: show.production.organization,
        production: show.production,
        regarding: show,
        message_type: :cast_contact
      )
    end

    # Send to all cast of a production (all shows)
    # Attaches the Production as the "regarding" object
    def send_to_production_cast(production:, sender:, subject:, body:)
      recipients = production.cast_users
      send_bulk(
        sender: sender,
        recipients: recipients,
        subject: subject,
        body: body,
        organization: production.organization,
        production: production,
        regarding: production,
        message_type: :cast_contact
      )
    end

    # Send to talent pool members
    # Attaches the Production as the "regarding" object
    def send_to_talent_pool(production:, sender:, subject:, body:, person_ids: nil)
      pool = production.effective_talent_pool
      people = person_ids ? pool.people.where(id: person_ids) : pool.people
      recipients = people.filter_map(&:user)

      send_bulk(
        sender: sender,
        recipients: recipients,
        subject: subject,
        body: body,
        organization: production.organization,
        production: production,
        regarding: production,
        message_type: :talent_pool
      )
    end

    # Send direct message (person to person)
    # No "regarding" object - just a direct conversation
    def send_direct(sender:, recipient_user:, subject:, body:, organization: nil)
      Message.create!(
        sender: sender,
        recipient: recipient_user,
        organization: organization,
        subject: subject,
        body: body,
        message_type: :direct
      )
    end

    # Generic bulk send with full control
    def send_bulk(sender:, recipients:, subject:, body:, message_type:,
                  organization: nil, production: nil, regarding: nil)
      messages = []
      recipients.uniq.each do |recipient_user|
        next unless recipient_user.is_a?(User)

        messages << Message.create!(
          sender: sender,
          recipient: recipient_user,
          organization: organization,
          production: production,
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

# Direct message between users
MessageService.send_direct(
  sender: Current.user.person,
  recipient_user: @other_person.user,
  subject: "Question about your availability",
  body: "Hey, I noticed you're marked as unavailable..."
)
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

### Database
| File | Purpose |
|------|---------|
| `db/migrate/xxx_create_messages.rb` | Messages table with regarding polymorphic |
| `db/migrate/xxx_add_message_preferences_to_users.rb` | User email delay preferences |
| `db/migrate/xxx_drop_forum_tables.rb` | Remove posts, post_views, forum fields |

### Models
| File | Purpose |
|------|---------|
| `app/models/message.rb` | Message model with regarding association |

### Controllers
| File | Purpose |
|------|---------|
| `app/controllers/my/inbox_controller.rb` | Inbox (list, show, archive, mark_read) |

### Views - Inbox (New)
| File | Purpose |
|------|---------|
| `app/views/my/inbox/index.html.erb` | Message list with unread indicators |
| `app/views/my/inbox/show.html.erb` | Message detail with regarding card |

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
| `app/jobs/message_email_reminder_job.rb` | Sends reminders for unread messages |

### Mailers
| File | Purpose |
|------|---------|
| `app/mailers/message_reminder_mailer.rb` | "You have unread messages" email |
| `app/views/message_reminder_mailer/unread_message.html.erb` | Reminder email template |
| `app/views/message_reminder_mailer/unread_message.text.erb` | Plain text version |

### Stimulus Controllers
| File | Purpose |
|------|---------|
| `app/javascript/controllers/message_compose_controller.js` | Modal and recipient selection |

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

Please confirm each item:

- [ ] **Forum removal**: Delete Post/PostView models, forum views, forum_mode/forum_enabled fields, all forum routes
- [ ] **User email history removal**: Delete all user-facing email viewing:
  - `/my/messages/emails` and `/my/messages/:id` - user's received emails
  - `/manage/communications` - production email logs
  - `/manage/org_communications` - org email logs
  - (Superadmin email monitor stays)
- [ ] **Unified MessageService**: Replace all "send message" email functions with `MessageService`:
  - `MessageService.send_to_show_cast(show:, ...)` - attaches Show as regarding
  - `MessageService.send_to_production_cast(production:, ...)` - attaches Production as regarding
  - `MessageService.send_to_talent_pool(production:, ...)` - attaches Production as regarding
  - `MessageService.send_direct(sender:, recipient_user:, ...)` - no regarding (direct message)
- [ ] **Regarding object**: Messages display a context card showing the related object (Show, Production, etc.)
- [ ] **Delete these mailers**: `Manage::ProductionMailer#send_message`, `CommunicationsMailer`, `My::TalentMessageMailer`
- [ ] **Email reminder delay**: 24 hours default before sending "you have unread messages" email
- [ ] **Keep transactional emails**: Auth, casting, show cancellation, vacancy, ticket, reminder emails stay as direct emails
- [ ] **New inbox location**: `/my/inbox` for message center
- [ ] **Move Questionnaires**: From `/manage/communications/` to `/manage/casting/` (under Casting module header)
- [ ] **Email reminder content**: Does NOT include message body, just "You have a new message from X - log in to view"

Once you confirm these, I'll implement in the phased order above.
