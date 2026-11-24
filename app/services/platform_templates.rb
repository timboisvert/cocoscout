# frozen_string_literal: true

# The words of the emails CocoScout sends about its own money, and the bank
# setup link a payee is sent, in one place (as TicketingTemplates and
# CourseTemplates are for theirs). Each is a seeded ContentTemplate.
class PlatformTemplates
  TEMPLATES = [
    # The 6-digit code for signing in, confirming a new account's address, and
    # (later) connecting a sign-in method (SignIn::Code). A code only, never a
    # link: mail scanners open links.
    { key: "auth_sign_in_code", name: "Sign-in code", channel: "email", category: "auth",
      subject: "{{code}} is your CocoScout code",
      body: %(<p>Your CocoScout code is:</p><p style="font-size:28px;font-weight:bold;letter-spacing:6px;margin:16px 0;">{{code}}</p><p>Enter it on the page that requested it. It works for {{lifetime}}, and only once.</p><p>If you didn't request a code, you can ignore this email. Nobody can get into your account without it.</p>),
      variables: [ { "name" => "code", "description" => "The 6-digit code" },
                   { "name" => "lifetime", "description" => "How long the code works, e.g. 10 minutes" } ] },
    # Apple or Google now signs someone in (SignIn::Connect): an email and a
    # notification each time, a deliberate exception to fewer emails (the
    # sign-in plan, Tim 2026-11-22), so a connection nobody made gets noticed.
    { key: "auth_method_connected", name: "Apple or Google connected", channel: "both", category: "auth",
      subject: "{{provider}} now signs you in to CocoScout",
      push_body: "{{provider}} now signs you in to CocoScout.",
      body: %(<p>Hi {{first_name}},</p><p>{{provider}} ({{provider_email}}) is now connected to your CocoScout account, so it signs you in with one tap. {{password_line}}</p><p>If you didn't connect it, sign in with a code, disconnect it on your <a href="{{account_url}}">Account page</a>, and write to support@cocoscout.com.</p>),
      variables: [ { "name" => "first_name", "description" => "Their first name" },
                   { "name" => "provider", "description" => "Apple or Google" },
                   { "name" => "provider_email", "description" => "The Apple or Google address, or \"a private Apple address\"" },
                   { "name" => "password_line", "description" => "Whether their password still works" },
                   { "name" => "account_url", "description" => "Their Account page" } ] },
    # A passkey now signs someone in (SignIn::Passkeys, PasskeysController):
    # an email and a notification, as for Apple or Google.
    { key: "auth_passkey_added", name: "Passkey added", channel: "both", category: "auth",
      subject: "A passkey now signs you in to CocoScout",
      push_body: "A passkey now signs you in to CocoScout.",
      body: %(<p>Hi {{first_name}},</p><p>A passkey ({{passkey_name}}) was added to your CocoScout account, so your face, fingerprint, or screen lock signs you in. Your email code always works too.</p><p>If you didn't add it, sign in with a code, remove it on your <a href="{{account_url}}">Account page</a>, and write to support@cocoscout.com.</p>),
      variables: [ { "name" => "first_name", "description" => "Their first name" },
                   { "name" => "passkey_name", "description" => "Where the passkey is kept, e.g. iCloud Keychain" },
                   { "name" => "account_url", "description" => "Their Account page" } ] },
    { key: "payee_bank_setup_link", name: "Bank setup link for a payee", channel: "email",
      subject: "{{organization_name}} wants to pay you through CocoScout",
      body: %(<p>Hi {{first_name}},</p><p>{{organization_name}} pays people through CocoScout, straight to their bank. Connect yours here. It takes a few minutes, and you don't need a CocoScout account.</p><p><a href="{{setup_url}}">Connect your bank</a></p><p>This link is just for you, so please don't forward it. It works for 30 days. If you weren't expecting it, you can ignore this email.</p>),
      variables: [ { "name" => "first_name", "description" => "The payee's first name" },
                   { "name" => "organization_name", "description" => "The organization paying them" },
                   { "name" => "setup_url", "description" => "Their own bank setup link (no sign-in; 30 days)" } ] },
    { key: "account_deletion_requested", name: "Someone requested account deletion", channel: "email",
      subject: "{{name}} requested deleting their CocoScout account",
      body: %(<p>{{name}} ({{email}}) requested deleting their CocoScout account from {{where}} on {{requested_on}}. They were told it would be done within 30 days, and can take it back from Account Settings until then.</p><p>Keep the payout and tax records the law needs; delete the rest from their Superadmin page.</p><p><a href="{{person_url}}">Open them in Superadmin</a></p>),
      variables: [ { "name" => "name", "description" => "Their name" },
                   { "name" => "email", "description" => "Their sign-in email" },
                   { "name" => "where", "description" => "The website, the iPhone app, or the Android app" },
                   { "name" => "requested_on", "description" => "The date of the request" },
                   { "name" => "person_url", "description" => "Their Superadmin page" } ] },
    { key: "cocoscout_money_check", name: "CocoScout money check needs a look", channel: "email",
      subject: "CocoScout's money check: {{headline}}",
      body: %(<p>This morning's check of CocoScout's Stripe balance against its records needs a look.</p>{{findings}}<p><a href="{{check_url}}">Open the Stripe check</a></p>),
      variables: [ { "name" => "headline", "description" => "One line: what's off" },
                   { "name" => "findings", "description" => "A list of what the check found" },
                   { "name" => "check_url", "description" => "The superadmin Stripe check page" } ] },
    { key: "org_monthly_statement", name: "Monthly CocoScout statement", channel: "email",
      subject: "Your CocoScout statement for {{month}}",
      body: %(<p>Hi {{first_name}},</p><p>Here's {{organization_name}}'s CocoScout statement for {{month}}. You paid CocoScout {{total_paid}}, and your CocoScout balance went from {{opening}} to {{closing}}. The statement is attached, and every statement is on your <a href="{{billing_url}}">Billing &amp; Plan page</a>.</p>),
      variables: [ { "name" => "first_name", "description" => "The billing contact's first name" },
                   { "name" => "organization_name", "description" => "The organization" },
                   { "name" => "month", "description" => "e.g. October 2026" },
                   { "name" => "total_paid", "description" => "What they paid CocoScout that month" },
                   { "name" => "opening", "description" => "CocoScout balance at the start of the month" },
                   { "name" => "closing", "description" => "CocoScout balance at the end of the month" },
                   { "name" => "billing_url", "description" => "Their Billing & Plan page" } ] },
    { key: "cocoscout_bill", name: "CocoScout bill issued", channel: "email",
      subject: "Your CocoScout bill: {{bill_title}}, {{amount}}",
      body: %(<p>Hi {{first_name}},</p><p>Here's {{organization_name}}'s CocoScout bill for <strong>{{bill_title}}</strong>: {{amount}}.</p>{{lines}}<p>{{how_paid}}</p><p>The invoice is attached (<a href="{{invoice_url}}">download it again</a>). Every bill is on your <a href="{{billing_url}}">Billing &amp; Plan page</a>.</p>),
      variables: [ { "name" => "first_name", "description" => "The billing contact's first name" },
                   { "name" => "organization_name", "description" => "The organization" },
                   { "name" => "bill_title", "description" => "What the bill is for, e.g. September 2026 usage" },
                   { "name" => "amount", "description" => "The amount, e.g. $41.00" },
                   { "name" => "lines", "description" => "What's on the bill, line by line" },
                   { "name" => "how_paid", "description" => "How and when it's paid" },
                   { "name" => "invoice_url", "description" => "CocoScout's invoice for the bill (PDF)" },
                   { "name" => "billing_url", "description" => "Their Billing & Plan page" } ] },
    { key: "cocoscout_bill_paid", name: "CocoScout bill paid (receipt)", channel: "email",
      subject: "Receipt: {{bill_title}}, {{amount}} paid",
      body: %(<p>Hi {{first_name}},</p><p>Your CocoScout bill for <strong>{{bill_title}}</strong> is paid: {{amount}}, on {{paid_on}}. Thank you.</p>{{lines}}<p>The invoice, marked paid, is attached (<a href="{{invoice_url}}">download it again</a>). Every bill is on your <a href="{{billing_url}}">Billing &amp; Plan page</a>.</p>),
      variables: [ { "name" => "first_name", "description" => "The billing contact's first name" },
                   { "name" => "organization_name", "description" => "The organization" },
                   { "name" => "bill_title", "description" => "What the bill is for, e.g. September 2026 usage" },
                   { "name" => "amount", "description" => "The amount paid, e.g. $41.00" },
                   { "name" => "paid_on", "description" => "The day it was paid" },
                   { "name" => "lines", "description" => "What was on the bill, line by line" },
                   { "name" => "invoice_url", "description" => "CocoScout's invoice for the bill (PDF)" },
                   { "name" => "billing_url", "description" => "Their Billing & Plan page" } ] },
    # A payment for a CocoScout bill failed (BillingInvoiceEmailJob): one email
    # for each failed attempt, stating what happens next. CocoScout's own,
    # since Stripe's emails to organizations are switched off (Tim, 2026-11-24).
    { key: "cocoscout_payment_failed", name: "CocoScout payment failed", channel: "email",
      subject: "Your CocoScout payment didn't go through: {{bill_title}}, {{amount}}",
      body: %(<p>Hi {{first_name}},</p><p>The payment for {{organization_name}}'s CocoScout bill for <strong>{{bill_title}}</strong>, {{amount}}, didn't go through.</p><p>{{next_step}}</p><p>You can pay the bill or update your payment method on your <a href="{{billing_url}}">Billing &amp; Plan page</a>.</p><p>Questions? Just reply to this email.</p>),
      variables: [ { "name" => "first_name", "description" => "The billing contact's first name" },
                   { "name" => "organization_name", "description" => "The organization" },
                   { "name" => "bill_title", "description" => "What the bill is for, e.g. September 2026 usage" },
                   { "name" => "amount", "description" => "The amount owed, e.g. $41.00" },
                   { "name" => "next_step", "description" => "Whether and when the payment is tried again" },
                   { "name" => "billing_url", "description" => "Their Billing & Plan page" } ] },
    # A yearly Pro plan renews in 30 days (ProRenewalReminder): once for each
    # renewal, with the amount Stripe will charge.
    { key: "cocoscout_pro_renewal", name: "Yearly Pro renewal reminder", channel: "email",
      subject: "CocoScout Pro renews on {{renews_on}}",
      body: %(<p>Hi {{first_name}},</p><p>{{organization_name}}'s yearly CocoScout Pro plan renews on <strong>{{renews_on}}</strong> for another year. {{charge_line}}</p><p>There's nothing to do to keep Pro. To change the payment method or cancel before then, choose <strong>Manage subscription</strong> on your <a href="{{billing_url}}">Billing &amp; Plan page</a>.</p><p>Questions? Just reply to this email.</p>),
      variables: [ { "name" => "first_name", "description" => "The billing contact's first name" },
                   { "name" => "organization_name", "description" => "The organization" },
                   { "name" => "renews_on", "description" => "The day the plan renews, e.g. December 24, 2026" },
                   { "name" => "charge_line", "description" => "What will be charged that day" },
                   { "name" => "billing_url", "description" => "Their Billing & Plan page" } ] },
    { key: "pro_comp_ending", name: "Complimentary Pro ending", channel: "email",
      subject: "Your complimentary CocoScout Pro ends {{ends_on}}",
      body: %(<p>Hi {{first_name}},</p><p>{{organization_name}}'s complimentary CocoScout Pro ends on <strong>{{ends_on}}</strong>, {{days_left}} from now.</p>{{value_lines}}<p>To keep all of it, choose <strong>Keep Pro</strong> on your <a href="{{keep_url}}">Billing &amp; Plan page</a>. Pro picks up the day your complimentary access ends, with nothing to set up again. {{price_line}}</p><p>If you don't, {{organization_name}} moves to the free Producer plan on {{ends_on}}, without:</p>{{lose_lines}}<p>Questions? Just reply to this email.</p>),
      variables: [ { "name" => "first_name", "description" => "The billing contact's first name" },
                   { "name" => "organization_name", "description" => "The organization" },
                   { "name" => "ends_on", "description" => "The day the complimentary Pro ends, e.g. December 31" },
                   { "name" => "days_left", "description" => "How long until then, e.g. 14 days" },
                   { "name" => "value_lines", "description" => "What Pro did for them in the last three months, as a list (empty when nothing happened)" },
                   { "name" => "price_line", "description" => "What Pro costs: the plan and the usage" },
                   { "name" => "lose_lines", "description" => "What they'd lose on Producer, as a list" },
                   { "name" => "keep_url", "description" => "Their Billing & Plan page, where Keep Pro is" } ] },
    # One email, once, to everyone with an account who hasn't opened the app
    # (AppAnnouncement). Its own links, so the layout leaves its footer line
    # about the app off. Tim and Andie's words (2026-11-13); the store badges
    # ride along inline (AppMailer's inline_images), since email apps don't
    # show SVG or web fonts.
    { key: "get_the_app_announcement", name: "CocoScout has an app", channel: "email",
      subject: "New: CocoScout app for iOS and Android",
      body: %(<p>Hello {{first_name}}!</p><p>Your pleas have been heard. The wait is over. The CocoScout app is now available for iOS and Android.</p><p>With this new mobile app, you’ll have the same functionality as the website, with the added benefit of real-time alerts and one-tap access that make CocoScout easier to use on the go.</p><p><strong>For performers:</strong> find auditions and mics, see your show/rehearsal schedule, communicate with fellow cast members and producers, get paid (and more!).</p><p><strong>For producers:</strong> cast your shows, manage communications, sell your tickets, pay your people (and more!).</p><p><strong>For venues:</strong> manage your contracts, staff your shows, sell your tickets, keep your books, pay your people (and more!).</p><p style="margin:16px 0 8px;line-height:0;font-size:0;"><a href="{{ios_url}}" style="display:inline-block;margin:0 8px 8px 0;text-decoration:none;"><img src="{{app_store_badge_src}}" alt="Download on the App Store" width="120" height="40" style="display:block;border:0;width:120px;height:40px;"></a><a href="{{android_url}}" style="display:inline-block;margin:0 0 8px 0;text-decoration:none;"><img src="{{google_play_badge_src}}" alt="Get it on Google Play" width="135" height="40" style="display:block;border:0;width:135px;height:40px;"></a></p><p>CocoScout is growing quickly, and we’re pleased to have you on our platform. Can’t wait to see the shows you and CocoScout put on together!</p><p>Andie and Tim and Coco</p>),
      variables: [ { "name" => "first_name", "description" => "Their first name" },
                   { "name" => "ios_url", "description" => "The App Store page" },
                   { "name" => "android_url", "description" => "The Google Play page" },
                   { "name" => "app_store_badge_src", "description" => "The App Store badge, attached to the email" },
                   { "name" => "google_play_badge_src", "description" => "The Google Play badge, attached to the email" },
                   { "name" => "app_url", "description" => "cocoscout.com/app: a phone goes to its own store" } ] }
  ].freeze

  def self.ensure!(keys: nil, overwrite: false)
    TEMPLATES.each do |spec|
      next if keys && !keys.include?(spec[:key])

      template = ContentTemplate.find_or_initialize_by(key: spec[:key])
      next if template.persisted? && !overwrite

      template.assign_attributes(name: spec[:name], category: spec[:category] || "payments", channel: spec[:channel], template_type: "structured",
                                 active: true, subject: spec[:subject], body: spec[:body], available_variables: spec[:variables])
      template.push_body = spec[:push_body] if spec[:push_body]
      template.save!
    end
  end
end
