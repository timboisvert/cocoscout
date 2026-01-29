# AWS SNS Setup for SMS Notifications

This guide covers setting up AWS SNS (Simple Notification Service) for sending SMS text messages from CocoScout.

## Overview

CocoScout uses AWS SNS to send transactional SMS messages for:
- **Show cancellations** - Notify cast members when a show is cancelled
- **Vacancy invitations** - Notify performers when they're invited to fill a vacancy
- **Vacancy filled** - Notify invited performers when a vacancy has been claimed

**Important:** We use **direct SMS publishing**, not SNS Topics. The SNS console defaults to showing Topics, but you can ignore that section entirely.

## Prerequisites: Origination Identity

Since 2023, AWS requires an "origination identity" (a registered phone number) to send SMS to US numbers. This is a carrier requirement to reduce spam.

**Recommended: Toll-Free Number**
- ~$2/month fee
- 1-3 business days for approval
- No brand registration required
- Good for low-to-medium volume

**Alternative: 10DLC**
- Lower per-message cost
- Requires brand + campaign registration
- 1-2 weeks for approval
- Better for high volume

This guide covers the **toll-free setup** (simpler for most use cases).

## Environment Variables

Add to your `.env` file (development) or deploy secrets (production):

```
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=abc123...
AWS_REGION=us-east-1
```

## Setup Steps

### 1. Create IAM User

1. Go to **AWS Console → IAM → Users → Create user**
2. Name: `cocoscout-sms` (or similar)
3. Click **Attach policies directly**
4. Click **Create policy** and use this JSON:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "sms-voice:SendTextMessage",
                "sms-voice:DescribePhoneNumbers"
            ],
            "Resource": "*"
        }
    ]
}
```

5. Name the policy `CocoScoutSMSPolicy` and create it
6. Attach it to your user
7. Go to **Security credentials** tab → **Create access key**
8. Select "Application running outside AWS"
9. Save the access key ID and secret access key

### 2. Request Toll-Free Number

1. Go to **AWS End User Messaging SMS** (search "End User Messaging" in AWS console)
2. In left sidebar, click **Phone numbers** → **Request phone number**
3. Select:
   - Country: **United States**
   - Number type: **Toll-free**
   - Default message type: **Transactional**
4. Click **Request**

The number will show as "Pending" initially.

### 3. Complete Toll-Free Verification

AWS requires verification for toll-free numbers to prevent abuse.

1. In End User Messaging → Phone numbers, click your new toll-free number
2. Click **Create registration** (or it may prompt automatically)
3. Fill out the registration form:

**Company Information:**
- Company name: Your company/organization name
- Company website: Your website URL
- Address: Your business address

**Use Case:**
- Use case category: **Account notifications**
- Use case description: Something like:
  > "Transactional notifications for a performing arts scheduling application. Users opt-in to receive SMS alerts for show cancellations and role vacancy invitations. Messages are sent only when users explicitly enable SMS notifications in their account settings."

**Message Samples (provide 2-3 examples):**

Include sender name, message content, link, and opt-out info:
```
CocoScout: Hamilton - Evening Show on Jan 30 cancelled. https://cocoscout.com/my Reply STOP to opt out.
```
```
CocoScout: Vacancy for Ensemble in Hamilton on Feb 15. https://cocoscout.com/claim/abc123 Reply STOP to opt out.
```
```
CocoScout: Vacancy filled - Ensemble for Hamilton on Feb 15. Reply STOP to opt out.
```

**Opt-in workflow description (max 500 characters):**

> Users opt-in at cocoscout.com/account/notifications by entering their phone number and viewing consent disclosures (program name, message frequency 0-5/month, data rates, STOP/HELP instructions, Terms & Privacy links, support contact). They must explicitly enable notifications via toggle. Messages are transactional only (show cancellations, vacancy invitations). Users opt out by replying STOP or disabling in settings.

**Opt-in screenshot:**
- Take a screenshot of `/account/notifications` showing:
  - Phone number input
  - Consent disclosure box with all required elements
  - Enable toggle switches
- Upload to the registration form

4. Submit the registration
5. Wait 1-3 business days for approval

### 4. Verify Setup Works

Once your toll-free number is approved (status shows "Active"):

1. Go to **Amazon SNS → Text messaging (SMS)** in left sidebar
2. Click **Publish text message** (for a quick test)
3. Select your toll-free number as the origination identity
4. Enter your phone number and a test message
5. Click **Publish message**

If you receive the text, your setup is complete.

### 5. Set Spend Limits (Optional)

To prevent unexpected charges:

1. Go to **Amazon SNS → Text messaging (SMS) → Text messaging preferences**
2. Set "Account spend limit" to your desired monthly maximum (e.g., $10.00)
3. AWS will stop sending SMS once the limit is reached

## Costs

**Toll-free number:** ~$2.00/month

**SMS messages (US):** ~$0.00645 per SMS segment (160 characters)

**Example:** 50 cast members × 2 messages/month = 100 messages
- Number fee: $2.00
- Messages: $0.65
- **Total: ~$2.65/month**

## Testing in Rails Console

```ruby
# Check if SNS is configured
SmsService.send(:sns_configured?)  # Should return true

# Send a test message
SmsService.send_sms(
  phone: "5551234567",  # Your verified phone
  message: "Test message from CocoScout",
  sms_type: "show_cancellation",
  user: User.first
)

# Check the result
SmsLog.last

# Check a user's SMS settings
user = User.first
user.sms_phone                                      # Phone number
user.sms_enabled?                                   # Master SMS toggle
user.sms_notification_enabled?("show_cancellation") # Specific notification
```

## Monitoring

### SMS Logs

All SMS attempts are logged to the `sms_logs` table and viewable at `/superadmin/sms_logs`.

Fields tracked:
- `phone` - Recipient phone number
- `message` - Message content
- `sms_type` - Type of notification (show_cancellation, vacancy_notification)
- `status` - pending, sent, or failed
- `sns_message_id` - AWS message ID (for sent messages)
- `error_message` - Error details (for failed messages)

### AWS CloudWatch

For detailed delivery metrics:
1. Go to **CloudWatch → Metrics → SNS**
2. View: NumberOfMessagesPublished, NumberOfNotificationsDelivered, NumberOfNotificationsFailed

## Troubleshooting

### "AWS SNS not configured"

Check environment variables are set:
```ruby
ENV["AWS_ACCESS_KEY_ID"].present?   # Should be true
ENV["AWS_SECRET_ACCESS_KEY"].present?
```

### "No origination entities available to send"

Your toll-free number isn't approved yet, or isn't in the same region. Check:
1. End User Messaging → Phone numbers → Status should be "Active"
2. Your AWS_REGION matches where you requested the number (usually us-east-1)

### "AuthorizationError"

- Verify IAM user has both `sns:Publish` and `sms-voice:*` permissions
- Check access key is active (not deleted/deactivated)

### Messages fail with "InvalidParameter"

- Verify phone number is 10 digits (US format)
- Phone must not include country code (SmsService adds +1 automatically)

### Messages not received (but show as "sent")

- Check AWS SNS delivery logs in CloudWatch
- Carrier may be filtering/blocking (try a different carrier to test)
- Verify recipient hasn't opted out of AWS SMS

### Toll-free registration rejected

Common reasons:
- Vague use case description (be specific about what triggers messages)
- Missing opt-in explanation (explain your settings page)
- Sample messages don't match stated use case

Resubmit with more detail about your transactional notification use case.
