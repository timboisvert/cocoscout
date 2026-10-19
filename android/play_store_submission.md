# Google Play submission: CocoScout for Android

Every answer Play Console asks for, in the order of its "Set up your app"
list. The images live in `android/play_store/` (not in git; regenerate from
the emulator if lost). The iOS answers are in `ios/app_store_submission.md`;
these match them, plus what the iOS ones missed (see "Data safety").

App: **CocoScout**, package `com.cocoscout.app`, free, organization account.

## Set up your app (Dashboard)

### Privacy policy

`https://cocoscout.com/privacy`

### App access

**All or some functionality in my app is restricted.** Add one set of
instructions:

- Name: `Reviewer account`
- Username: `app.review@demo.cocoscout.com`
- Password: `Lantern-Street-2026!` (the reviewer block's default in
  `ios/app_store_submission.md`)
- Any other information (500 characters at most; this is 482):

```
Free app for performers and crew. This account is a performer at a sample organization.
- Menu: pink cat button, bottom right.
- Messages: a thread from the manager; replies work.
- Door: Menu > Work the door > the show. Scan opens the camera (the camera permission). Tap a party to check it in. Sell records cash and comp sales; card payments aren't set up for this sample.
- Organization tools are a website and open in the browser.
- Delete account: Settings > Delete my account.
```

The sample shows on sale are dated from the day the reviewer block last ran
(on 2026-10-15: Oct 15, 18 and 25). **Re-run the block the day you send the
app for review** so the Door has a show to open through a week of review.

### Ads

**No, my app does not contain ads.**

### Content rating

Start the questionnaire. Email `support@cocoscout.com`. Category: **All Other
App Types**.

| Question | Answer |
|---|---|
| Violence, blood, sexual content, nudity, language, drugs, alcohol, tobacco, crude humor | No (all) |
| Gambling, simulated gambling | No |
| Users can interact or exchange content (chat, messages, sharing photos) | **Yes** |
| Shares the user's current physical location with other users | No |
| Lets users purchase digital goods | No |
| Unrestricted internet access / a web browser | No |
| Is the app a news app or contains news content | No |

Expect Everyone / PEGI 3 with "Users Interact".

### Target audience and content

- Target age groups: **18 and over** only. (The privacy policy says it isn't
  for under-13s; picking only 18+ keeps the app out of Google's Families
  program.)
- Could the app unintentionally appeal to children: **No**.

### News apps

**No.**

### Data safety

**Data collection and security**

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | Yes |
| Is all of the user data collected by your app encrypted in transit? | Yes |
| Account creation methods | Username and password (the sign-in is email and password) |
| Delete account URL | `https://cocoscout.com/support#delete-account` |
| Can users ask for some data to be deleted without deleting their account? | No |

**Data types.** Every row: Collected **yes**, Shared **no**, Processed
ephemerally **no**. "Shared" stays no: organizations a person joins see what
they chose to share with them (user-initiated), and the companies that run
CocoScout's servers, email and payments are service providers, which Google
doesn't count as sharing.

| Category → type | Required or optional | Purposes |
|---|---|---|
| Personal info → Name | Required | App functionality, Account management |
| Personal info → Email address | Required | App functionality, Account management |
| Personal info → User IDs | Required | App functionality, Account management |
| Personal info → Address | Optional | App functionality, Fraud prevention, security and compliance |
| Personal info → Phone number | Optional | App functionality |
| Personal info → Other info | Optional | App functionality, Fraud prevention, security and compliance |
| Financial info → Purchase history | Optional | App functionality |
| Messages → Other in-app messages | Optional | App functionality |
| Photos and videos → Photos | Optional | App functionality |
| Files and docs | Optional | App functionality |
| App activity → Other user-generated content | Optional | App functionality |
| Device or other IDs | Optional | App functionality |

What each one is, if Google asks:
- Address and Other info: the mailing address and taxpayer ID number on a
  W-9, needed before an organization pays someone; pronouns.
- Purchase history: course registrations and contract payments made through
  the app (the card itself is entered on the payment provider's page).
- Photos: headshots and photos sent in messages. Files and docs: résumés.
  Other user-generated content: profile bio and credits.
- Device or other IDs: the notification token.

Not collected: location, financial payment info (cards and bank details are
entered on the payment provider's own page), health, contacts, calendar,
audio, web browsing, app interactions, crash logs and diagnostics (no
analytics or crash SDK in the app), advertising ID.

### Government apps

**No.**

### Financial features

**My app doesn't provide any financial features.** The door sells an
organization's own event tickets (like any merchant), and payouts are set up
on the payment provider's page, not in the app.

### Health apps

**My app does not have any health features.**

### Advertising ID

**No.** The app doesn't use it (the built app has no `AD_ID` permission).

### App category and contact details (Store settings)

- App or game: App. Category: **Business**.
- Tags: pick up to five that fit from Google's list (event management,
  business, productivity).
- Email: `support@cocoscout.com`. Website: `https://cocoscout.com`. Phone:
  leave blank.
- External marketing: off.

## Store listing (Grow users → Store presence → Main store listing)

| Field | Value |
|---|---|
| App name (30) | CocoScout |
| Short description (80) | Your shows, your messages, your ticketing. All in one place. |
| App icon | `play_store/icon-512.png` |
| Feature graphic | `play_store/feature-graphic.png` |
| Phone screenshots | `play_store/1-welcome.png` through `5-door.png`, in order |
| Tablet screenshots | none (phone-only, portrait) |
| Video | none |

### Full description (4000)

```
CocoScout is where performers, crew and the organizations they work with keep everything about a show in one place. The app brings the performer side to your phone.

YOUR CALENDAR
Every show, rehearsal and shift you're on, with call times, locations and who else is cast, plus the availability questions your organizations ask.

MESSAGES THAT REACH YOU
Cast messages, casting news, sign-up confirmations and contract requests arrive as notifications, and open straight to the thread.

SIGN-UPS AND AUDITIONS
Sign up for open mics and showcases, submit for auditions, and see where you stand.

CONTRACTS, DOCUMENTS AND PAY
Sign agreements, pick up scripts and schedules, finish your tax forms, and see what you've been paid.

THE DOOR
Working the box office tonight? The app scans tickets with the camera, checks in whole parties, and sells at the door.

CocoScout is free for performers. Organizations manage casting, ticketing and payouts from the web at cocoscout.com; sign in there with the same account.
```

## The first release

1. **Internal testing** first (Testing → Internal testing → Create new
   release). Upload `app-release.aab`. It's live to testers in minutes, with
   no review, and Google runs its pre-launch report on real devices. The
   upload also makes Google's app signing key, whose SHA-256 goes into
   `/.well-known/assetlinks.json` so cocoscout.com links open in the app.
2. **Production** next (Production → Create new release → promote the same
   build). Countries: United States (add more any time). Release name `1.0`.
   Release notes:

```
The first CocoScout app: your calendar, messages, sign-ups, contracts and pay, with notifications for the things that matter and a scanner for the door.
```

New apps from new developer accounts can take up to a week in review.

## Building the release

The upload key is `android/keystores/cocoscout-upload.jks`; its passwords
are in `android/keystore.properties`. Neither is in git; both are saved in
1Password as "CocoScout Android upload key". If they're lost, Play
Console can reset the upload key (Setup → App signing); the app signing key
itself is Google's and can't be lost.

```bash
cd android && JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew bundleRelease
```

The bundle lands at `android/app/build/outputs/bundle/release/app-release.aab`.
Bump `versionCode` in `app/build.gradle.kts` for every upload (Play refuses
a number it has seen).

## Tap to Pay (version 1.2, build 3)

The door phone takes a buyer's card or phone tap (`door/TapToPayReader`).
Android has no approval step like Apple's: the moment this build reaches
someone with box office access at an organization that has Tap to Pay
switched on (Stars & Garters today), they see it in the menu and at the door.

The bundle is built: `app-release.aab` as above, versionCode 3, versionName
1.2. Two things first:

- **Deploy main.** The Android wording ("Tap to Pay", never the iPhone) and
  the door header fix are on the server; without them the app says "Tap to
  Pay on iPhone". Film Apple's Recording 4 (`ios/tap_to_pay.md`) before
  this deploy: main also adds a "Tap to Pay on Android" card to the Door tab
  that recording shows.
- **Let build 2 (1.0) pass its review first.** A new Production release
  replaces one that's still in review. Internal testing doesn't have to wait.

1. **Internal testing.** Testing → Internal testing → Create new release →
   upload `app-release.aab`, release name `1.2`. Add Andy's Google account
   to the testers list and copy the "Join on the web" link.
2. **Andy's phone.** Stripe's list (checked 2026-10-19):
   - Android 13 or later, with a security update from the last 12 months
     (Settings → About phone, and Settings → Security).
   - NFC on (search Settings for "NFC").
   - Google Play Store on the phone, not rooted, the maker's own Android.
   - Developer options off (Settings → System → Developer options; if it
     isn't listed, it's off).
   - Location on (Settings → Location).
   - For cards that ask for a PIN: no screen recording, no accessibility or
     draw-over-other-apps tools running.

   Supported phones include Pixel 6 and later and Galaxy S22 and later; the
   full list is on [Stripe's Tap to Pay page](https://docs.stripe.com/terminal/payments/setup-reader/tap-to-pay?platform=android#supported-devices).
   Open the testing link on the phone and install from Play, not from a
   copied file. If CocoScout 1.0 is on it, Play updates it.
3. **Set it up.** Sign in as someone with box office access at Stars &
   Garters. Menu → Tap to Pay → Set up Tap to Pay → allow location "While
   using the app". It says Ready within a few seconds.
4. **One real tap at a door.** Work the door → the show → Sell → 1 ticket →
   Tap to Pay. Stripe's tap screen shows where to tap; tap a real card (or a
   phone wallet). The page says Paid with the receipt code. Note the order
   code.
5. **Refund it** on the website: Manage → Ticketing → Orders → that order →
   Refund.
6. **Production.** Production → Create new release → add build 3 (1.2)
   from the library. Release notes:

```
Tap to Pay at the door: box office staff can take a buyer's contactless card or phone wallet right on their Android phone.
```

**Play Console for this build**

- No new permission declaration. Location is approximate and only while
  the app is open (no background location). Stripe's SDK also declares NFC,
  phone state and Bluetooth, none of which has a Play form.
- **Data safety: three changes.** Add Location → Approximate location
  (Collected, not shared, Optional; App functionality, and Fraud
  prevention, security and compliance): card networks need to know where a
  payment is taken. Add Financial info → User payment info (Optional, same
  purposes): the card a buyer taps, read on the payment provider's own
  screen and sent to it encrypted; CocoScout never sees the number. On
  Device or other IDs, add the purpose Fraud prevention, security and
  compliance: the payment SDK checks the phone.
- Financial features: unchanged, "My app doesn't provide any financial
  features." Tap to Pay is an organization taking payment for its own
  tickets, like the door's other ways to pay. If Google asks, the nearest
  category is Payments and transfers → Mobile payments and digital wallets.
- Content rating: unchanged.

The emulator can't run Tap to Pay, even Stripe's simulated reader (it has
no NFC), so a debug build there stands Stripe's simulated countertop reader
in for it, with a dialog playing the buyer. That's for testing on the Mac
only; release builds never do it.
