# Email Tracking System

## Overview
Every email sent by the application is automatically logged to the `email_logs` table with full tracking information including user, recipient, subject, body, and delivery status.

## Database Schema

### `email_logs` table
- `user_id` - Foreign key to users table (the user associated with this email)
- `recipient` - Email address of the recipient
- `subject` - Email subject line
- `body` - Full email body (text or HTML)
- `mailer_class` - The mailer class that sent the email (e.g., "AuthMailer")
- `mailer_action` - The mailer action/method (e.g., "signup")
- `message_id` - Unique message ID from the email
- `delivery_status` - Current status: "pending", "sent", "delivered", "failed"
- `sent_at` - Timestamp when email was sent
- `delivered_at` - Timestamp when email was delivered (if known)
- `error_message` - Error message if delivery failed

## How It Works

### 1. ApplicationMailer Enhancement
`app/mailers/application_mailer.rb` overrides the `mail()` method to automatically add user tracking headers:
- `X-User-ID` - The ID of the user associated with this email
- `X-Mailer-Class` - The mailer class name
- `X-Mailer-Action` - The action/method name

The `find_user_from_params` method extracts the user from common instance variables:
- `@user` - Direct user object
- `@person.user` - User via person association
- `@team_invitation.user` - User via team invitation
- `@person_invitation.user` - User via person invitation
- `@sender` - Sender user object

### 2. Email Log Interceptor
`app/mailers/email_log_interceptor.rb` intercepts all outgoing emails via ActionMailer's interceptor mechanism. The `delivering_email` method:
1. Extracts the user ID from the `X-User-ID` header
2. Creates an `EmailLog` record with all email details
3. Gracefully handles errors without preventing email delivery

### 3. Automatic Registration
`config/initializers/email_log_interceptor.rb` registers the interceptor with ActionMailer on application boot.

## Viewing Email Logs

### God Mode Interface
Visit `/god_mode/email_logs` to view all email logs. Features:
- Shows 100 most recent emails
- Filter by user ID
- Filter by recipient email address
- Display sent timestamp, user, recipient, subject, mailer info, and delivery status
- Click on user email to filter by that user

### Programmatic Access

```ruby
# Get all emails for a user
user = User.find(123)
emails = user.email_logs.recent

# Get recent emails
recent_emails = EmailLog.recent.limit(50)

# Get sent emails
sent_emails = EmailLog.sent

# Get failed emails
failed_emails = EmailLog.failed

# Search by recipient
emails_to_person = EmailLog.where("recipient LIKE ?", "%john@example.com%")
```

## Testing

Run the spec to verify email tracking:
```bash
bundle exec rspec spec/mailers/email_log_interceptor_spec.rb
```

The test suite verifies:
- Email logs are created when emails are sent
- User association is correct
- All metadata is captured
- Email delivery continues even if logging fails

## Current Mailers

All these mailers automatically log emails:
- `AuthMailer` - signup, password reset
- `Manage::TeamMailer` - team invitations
- `Manage::PersonMailer` - person invitations, contact emails
- `Manage::AuditionMailer` - casting notifications, audition invitations
- `Manage::AvailabilityMailer` - availability requests

## Notes

- **Non-blocking**: Email logging errors never prevent email delivery
- **Automatic**: No code changes needed in individual mailers
- **Comprehensive**: Captures all email details including full body content
- **Privacy**: God mode access required to view logs
- **Performance**: Uses database indexes for efficient querying

## Future Enhancements

Possible improvements:
1. Webhook receivers for delivery status updates from email service
2. Email open tracking (requires tracking pixel)
3. Click tracking for links in emails
4. Email templates preview in the logs view
5. Export functionality for email logs
6. Retention policy for old email logs
