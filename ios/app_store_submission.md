# App Store submission — CocoScout for iPhone

Everything written that App Store Connect asks for, so submission is a
paste job once the screenshots exist (they need the Simulator on a Mac).
Ship v1 without Tap to Pay: it needs the Stripe Terminal SDK built in on a
Mac, a How-to-Tap screen, and Apple's review of the entitlement in use; the
server half is in place (see `ios/tap_to_pay.md`) and can
ship as 1.1 without a listing change.

## The listing

| Field | Value |
|---|---|
| Name | CocoScout |
| Subtitle (30) | Your shows, cast and door |
| Bundle ID | com.cocoscout.app |
| Version | 1.0 (build 4 — bump `CURRENT_PROJECT_VERSION` before the upload) |
| Primary category | Business |
| Secondary category | Entertainment |
| Age rating | 4+ (no objectionable content, no gambling, no unrestricted web) |
| Price | Free |
| Copyright | 2026 CocoScout |
| Privacy policy URL | https://cocoscout.com/privacy |
| Support URL | https://cocoscout.com/support |
| Marketing URL | https://cocoscout.com |

The support page is /support (support@cocoscout.com, the common questions, links to privacy and terms); it's linked from the site footer.

### Keywords (100 characters, comma-separated, no spaces)

```
theater,theatre,casting,audition,signup,cast,crew,show,tickets,box office,door,check-in,comedy,improv
```

### Promotional text (170, can change without a new build)

Everything about the shows you're in, in your pocket: your calendar, your
cast messages, call times, sign-ups, contracts and pay. Working the door?
Scan tickets right from the app.

### Description

CocoScout is where performers, crew and the organizations they work with
keep everything about a show in one place. The app brings the performer side
to your phone.

YOUR CALENDAR
Every show, rehearsal and shift you're on, with call times, locations and
who else is cast, plus the availability questions your organizations ask.

MESSAGES THAT REACH YOU
Cast messages, casting news, sign-up confirmations and contract requests
arrive as notifications, and open straight to the thread.

SIGN-UPS AND AUDITIONS
Sign up for open mics and showcases, submit for auditions, and see where you
stand.

CONTRACTS, DOCUMENTS AND PAY
Sign agreements, pick up scripts and schedules, finish your tax forms, and
see what you've been paid.

THE DOOR
Working the box office tonight? The app scans tickets with the camera,
checks in whole parties, and sells at the door.

CocoScout is free for performers. Organizations manage casting, ticketing
and payouts from the web at cocoscout.com; sign in there with the same
account.

### What's new (1.0)

The first CocoScout app: your calendar, messages, sign-ups, contracts and
pay, with notifications for the things that matter and a scanner for the
door.

## App Review information

Sign-in required: yes. Demo account: the reviewer account the block below
creates on production (email and password print when it runs). Give App
Review the email, the password, and these notes:

> CocoScout is a free companion app for performers and crew. The account
> above is a performer cast in upcoming shows at a sample organization.
>
> - Sign in with the email and password. The menu (top left) lists
>   everything: Calendar, Messages, Shows, and so on.
> - Messages has a thread from the organization's manager; replies work.
> - "Manage" (the organization's side: casting, ticketing, payouts) is
>   deliberately a website, not part of the app. Any link to it opens in
>   Safari. There is no in-app purchase, nothing is sold inside the app, and
>   no money changes hands in it.
> - Door: the account also has box-office access to the sample shows.
>   Open the menu → "Work the door" at the bottom → the show. "Scan" opens
>   the camera (that is the camera permission);
>   the list shows two parties with tickets you can check in by tapping, and
>   "Sell" records cash and comp sales. The "Card or phone pay" option shows
>   a QR code for the buyer's own phone; the sample organization has no
>   Stripe account, so it will say card payments aren't set up — expected.
> - Notifications: allowing them is optional; the app works without.
> - Account deletion: Settings → Delete my account files a request we
>   complete within 30 days, as the listing says.

Contact: Tim Boisvert, boisvert@gmail.com, (phone).

## App Privacy (the questionnaire)

Matches `ios/CocoScout/PrivacyInfo.xcprivacy` exactly.

**Do you or your third-party partners collect data from this app?** Yes.

| Data type | Collected | Linked to the user | Used for tracking | Purposes |
|---|---|---|---|---|
| Contact Info → Name | Yes | Yes | No | App Functionality |
| Contact Info → Email Address | Yes | Yes | No | App Functionality |
| Contact Info → Phone Number | Yes | Yes | No | App Functionality |
| User Content → Photos or Videos (headshots) | Yes | Yes | No | App Functionality |
| User Content → Other User Content (messages, profile text) | Yes | Yes | No | App Functionality |
| Identifiers → User ID (the account) | Yes | Yes | No | App Functionality |
| Identifiers → Device ID (the push token) | Yes | Yes | No | App Functionality |

Everything else: not collected. In particular —

- Financial Info: no. Bank details for payouts are entered on Stripe's own
  page in a secure sheet; card payments by ticket buyers happen on their
  phone in Safari, not in the app. CocoScout never sees a card number.
- Location: no. The door scanner uses the camera, not location.
- Purchases: no — nothing is sold in the app.
- Usage Data, Diagnostics, Crash data: no — there is no analytics or crash
  SDK in the app (Sentry runs on the server only).
- Contacts, Health, Browsing/Search history, Sensitive Info: no.
- Tracking: no. `NSPrivacyTracking` is false and there are no tracking
  domains.

User ID is declared (the conservative reading: a signed-in phone is tied to an account), so answer Yes to it here.

Required reason APIs: UserDefaults, reason CA92.1 (the app's own settings:
the cached menu and the push token). Already in the manifest.

## The reviewer account

One block, run on production. It creates a sample organization on the demo
email domain (so the superadmin metrics ignore it), a manager, the reviewer
as a performer cast in four shows, a message thread, tonight's show and
the next two (three and ten days out) on sale, each
with two paid parties to check in, and box-office door access for the
reviewer. Run it dry first; it prints what it would make and rolls back.

```sh
kamal app exec -i --reuse 'bin/rails runner -' <<'RUBY'
DRY_RUN = true   # run once, read the output, then set false and run again

REVIEW_DOMAIN = "demo.cocoscout.com"
REVIEWER_EMAIL = "app.review@#{REVIEW_DOMAIN}"
MANAGER_EMAIL  = "stage.manager@#{REVIEW_DOMAIN}"
PASSWORD = ENV.fetch("REVIEW_PASSWORD") { "Lantern-Street-2026!" }
ORG_NAME = "Lantern Street Players (App Review)"
tz = ActiveSupport::TimeZone["America/New_York"]

say = ->(line) { puts "  #{line}" }
puts DRY_RUN ? "DRY RUN — nothing will be kept" : "Creating the App Review account"

ActiveRecord::Base.transaction do
  user_for = lambda do |email|
    User.find_by(email_address: email) || User.create!(email_address: email, password: PASSWORD, password_confirmation: PASSWORD,
                                                       last_seen_at: Time.current)
  end
  manager_user  = user_for.call(MANAGER_EMAIL)
  reviewer_user = user_for.call(REVIEWER_EMAIL)
  reviewer_user.update!(password: PASSWORD, password_confirmation: PASSWORD) # always the password above
  say.call "users: #{manager_user.email_address}, #{reviewer_user.email_address}"

  org = Organization.find_by(name: ORG_NAME) ||
        Organization.create!(name: ORG_NAME, owner: manager_user, talent_pool_mode: "per_production")
  OrganizationRole.find_or_create_by!(organization: org, user: manager_user) { |r| r.company_role = "manager" }
  say.call "organization: #{org.name} (#{org.id})"

  person_for = lambda do |user, name|
    person = Person.find_by(user: user) || Person.create!(user: user, name: name, email: user.email_address)
    org.people << person unless org.people.include?(person)
    user.update!(default_person: person) if user.default_person.nil?
    person
  end
  manager  = person_for.call(manager_user, "Morgan Field")
  reviewer = person_for.call(reviewer_user, "Jordan Reviewer")

  location = org.locations.find_by(name: "Lantern Street Playhouse") ||
             Location.create!(organization: org, name: "Lantern Street Playhouse", address1: "48 Lantern Street",
                              city: "Providence", state: "RI", postal_code: "02903", default: true)

  production = org.productions.find_by(name: "An Evening of Sketch") ||
               Production.create!(organization: org, name: "An Evening of Sketch", production_type: "in_house",
                                  description: "A rotating night of new sketch comedy.", show_cast_members: true)
  ensemble = production.roles.find_by(name: "Ensemble") ||
             Role.create!(production: production, name: "Ensemble", quantity: 6, category: "performing")

  tonight = tz.now.change(hour: 19, min: 30)
  shows = [ tonight - 4.days, tonight, tonight + 3.days, tonight + 10.days ].map do |at|
    # The sample organization is on the free plan, whose 6-events-a-month cap
    # stops a re-run late in the month; it's a demo, so skip just that check.
    show = production.shows.find_by(date_and_time: at) ||
           Show.new(production: production, date_and_time: at, event_type: "show", location: location, casting_enabled: true).tap do |s|
             s.define_singleton_method(:within_free_event_limit) { nil }
             s.save!
           end
    ShowPersonRoleAssignment.find_or_create_by!(show: show, role: ensemble, assignable: reviewer) { |a| a.position = 0 }
    show
  end
  say.call "shows: #{shows.map { |s| s.date_and_time.in_time_zone(tz).strftime('%a %b %-d %-l:%M %p') }.join(', ')} — reviewer cast as Ensemble"

  unless Message.exists?(organization: org, subject: "Welcome to the run!")
    root = MessageService.send_direct(sender: manager_user, recipient_person: reviewer, subject: "Welcome to the run!",
                                      body: "<p>Hi Jordan — so glad you're in. Call is 6:30 on show nights; the stage door is on Lantern Street. Shout if you need anything.</p>",
                                      organization: org, production: production)
    MessageService.reply(sender: reviewer_user, parent_message: root, body: "<p>Thanks Morgan! See you at 6:30.</p>")
    say.call "message thread: \"Welcome to the run!\" with one reply"
  end

  profile = TicketingProfile.for(org)
  profile.update!(enabled: true, door_in_app: "always") # the reviewer finds the Door whatever day they look
  # Tonight's show and the next two (three and ten days out) are on sale;
  # tonight's has two parties sold at the door (tickets still to scan).
  listings = [ shows[1], shows[2], shows[3] ].map do |show|
    listing = TicketListing.find_by(show: show) || TicketListing.create!(show: show, status: "on_sale")
    general = listing.ticket_tiers.find_by(name: "General") || listing.ticket_tiers.create!(name: "General", price_cents: 1_500, quantity: 60)
    listing.update!(status: "on_sale")
    # Only once the door is open: ahead of it a door sale is a presale that
    # emails the buyer. Re-run on a later day and that day's parties are added.
    if listing.ticket_orders.none? && !listing.door_ahead?
      door = TicketDoor.new(listing, manager_user)
      { "Avery Patel" => 2, "Sam Okafor" => 3 }.each do |name, count|
        order = door.sell({ general.id.to_s => count.to_s }, kind: "cash", buyer_name: name)
        order.tickets.update_all(status: "valid", checked_in_at: nil, checked_in_by_id: nil)
      end
    end
    say.call "on sale: #{listing.display_title} #{show.date_and_time.in_time_zone(tz).strftime('%a %b %-d')} (listing #{listing.id}), General $15 × 60, parties Avery Patel (2) and Sam Okafor (3)"
    listing
  end

  grant = org.ticketing_access_grants.where(revoked_at: nil).find_or_initialize_by(user: reviewer_user)
  grant.update!(access_level: "box_office", granted_by: manager_user)
  say.call "door access: #{reviewer_user.email_address} box office at #{org.name}"

  puts
  puts "App Review sign-in: #{REVIEWER_EMAIL} / #{PASSWORD}"
  puts "Door URLs: " + listings.map { |listing| "https://cocoscout.com/door/#{listing.id}" }.join(", ")
  raise ActiveRecord::Rollback if DRY_RUN
end
puts(DRY_RUN ? "Rolled back." : "Done.")
RUBY
```

If `rails runner -` isn't accepted on the deployed Rails, run
`kamal app exec -i --reuse 'bin/rails console'` and paste the block instead.

After a real run: the reviewer's password is in the output; change the
`REVIEW_PASSWORD` if you'd rather not keep the default. To undo, delete the
organization from Superadmin → Organizations (the two users are on the demo
domain and can stay).

The shows on sale are "tonight", three days later and ten days later,
relative to the day the block runs, so run it the day you submit. If review
drags past the last one, re-run it (it's idempotent: it only adds what's missing and
re-dates nothing) the day before, and it adds the next dates.

## Still needs a Mac

- Screenshots: 6.9" and 6.1" iPhone sets from the Simulator (menu, My
  Calendar, a message thread, the door list, the scanner). iPad isn't
  required while the app is iPhone-only.
- Submit build 5 (`CURRENT_PROJECT_VERSION = 5`; it adds the location and
  Bluetooth purpose strings App Store Connect asked for on build 4). Bump to
  6 for the next upload.
- v1 ships without Tap to Pay: release builds leave it out until Apple
  grants the distribution entitlement (ios/tap_to_pay.md). Still to build
  for that: Apple's How to Tap screen.
