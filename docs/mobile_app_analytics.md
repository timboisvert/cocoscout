# Tracking usage of the mobile apps

Researched 2026-10-28, for Tim's question: "how can we track usage of this
app? Are there any free options these days?" Nothing here is built yet; this
is the recommendation to pick from.

## Where we are today

- **No analytics in either app.** The iOS privacy label and
  `ios/CocoScout/PrivacyInfo.xcprivacy` say Usage Data and Diagnostics are not
  collected (`ios/app_store_submission.md`, "App Privacy"); Android's Data
  safety form says the same. The Android app already carries Firebase, but only
  Cloud Messaging for push.
- **Google Analytics (G-P198QVDCDH) is on the website only**, in
  `layouts/application.html.erb` and `layouts/home.html.erb`. The app renders
  with `layouts/native.html.erb`, which has no gtag, so app traffic never
  reaches GA.
- **The server already knows every app request.** Every screen is a page from
  cocoscout.com. `turbo_native_app?` (user agent contains "Turbo Native")
  marks it, `native_android?` tells Android from iPhone, and app builds from
  V1.1 on put `CocoScout/<version> (<build>; nav <n>)` in front of the user
  agent (`ios/CocoScout/AppConfig.swift`, `android/.../AppConfig.kt`), which
  `NativeAppVersion` reads. V1 builds send no version, so "no version" means V1.
- **What we can already count, roughly:**
  - `users.last_seen_at` (`ActivityTracking`, every 15 minutes): when someone
    was last active, but not whether it was the app or the website.
  - `sessions.user_agent`: who has ever signed in from the app. `created_at`
    only, so it says nothing about later use.
  - `app_sessions` (one per signed-in phone, `last_used_at`): only touched by
    the token API (sign-in, push registration), not by page views, so it
    undercounts use.
  - Rails/kamal-proxy logs carry the user agent, but they're kept for minutes.

So today we can say "this many people have signed in on the app", not "this
many people used it this week".

## The options

| Option | What it tells us | Cost | Needs from Tim | Needs a new app build? | Privacy |
|---|---|---|---|---|---|
| **App Store Connect Analytics** | Impressions, product page views, downloads, re-downloads, deletions, sessions, active devices, retention by download cohort, crashes. Usage numbers only cover people who chose to share analytics with developers. | Free | Sign in and look (App Analytics) | No | Nothing to change: Apple collects it |
| **Google Play Console statistics** | Installs, uninstalls, installed audience, daily and monthly active users, monthly returning users, crashes and ANRs (Android vitals). | Free | Sign in and look (Statistics, Android vitals) | No | Nothing to change: Google collects it |
| **Our own server-side app usage** (recommended build) | Daily/weekly/monthly active app users, iPhone vs Android, which app versions are still in use (how many V1 installs remain), retention by first app day, the pages used most in the app, all tied to our own users and organizations. Not installs: the stores have those. | Free (a small table on our database) | Update both stores' privacy answers (below) | No: it's all server code | First-party only; nothing leaves our servers |
| GA4 in the app's layout | Page views and events in GA's reports, split by a custom "platform" dimension. Same pages we'd see server-side, in Google's UI. | Free | Privacy answers now say a third party (Google) collects usage data; set up a separate data stream | No (web layout change) | Sends app usage to Google; GA's cookie identity in a web view is shaky |
| Firebase Analytics (GA4 for apps) | first_open, engagement time, retention cohorts, DAU/MAU per platform, plus whatever screens we log by hand (Hotwire screens aren't native, so auto screen tracking sees one screen). | Free | Firebase project for iOS too, privacy labels, an Apple and a Google review | **Yes, both apps** | Google SDK in the app; app-instance IDs go to Google |
| PostHog Cloud | Product analytics, funnels, retention; also session replay. Free tier is about 1M events and 5K recordings a month. | Free at our size | Account, privacy labels, data processing terms | No if added to the web layout; yes for its native SDKs | Third party; replay would record W-9s, payouts and messages, so it must stay off |
| TelemetryDeck | Privacy-first native analytics (Swift/Kotlin SDKs, anonymized IDs). Its July 2026 pricing change shrank the free plan for new accounts. | Probably a small monthly fee now | Account, privacy labels, reviews | **Yes, both apps** | Very good, but it's native-first and our screens are web pages |
| Plausible CE / Umami (self-hosted) | Simple page-view analytics. Umami Cloud's Hobby plan is free (about 100K events a month by third-party counts). | Free software, but self-hosting means a new server to run | A server (provisioning checklist) or an Umami account, privacy labels | No (web layout change) | Good: no cookies, no personal data, but page views only |

## Recommendation

**Start with two things, both free:**

1. **The two store dashboards, today (Tim only, no code).** They're the only
   source for installs, deletions and crash rates, and they already have data
   from launch day.
2. **First-party app usage on our own server (Claude builds it, no app build,
   no review).** Because every app screen is one of our pages, the server sees
   every use already. Write it down once a day per person and we get real
   active-user counts, the iPhone/Android split, the versions in use, and the
   pages people use in the app, with nothing sent to anyone else and no new
   SDK for Apple or Google to review.

Skip GA4, Firebase, PostHog and TelemetryDeck for now: each sends app usage to
a third party (bigger privacy-label change) and mostly repeats what the server
already sees. Firebase and TelemetryDeck also need new builds and reviews in
both stores. Revisit if we ever want funnels or a richer dashboard than the
superadmin page.

## Steps

### What only Tim can do

1. **App Store Connect → Apps → CocoScout → Analytics.** Look at Overview,
   then Metrics: downloads, deletions, sessions, active devices, retention.
   Usage figures only count people who share analytics with developers, so
   treat them as a sample. Crash reports from App Store users are in Xcode →
   Window → Organizer → Crashes.
2. **Play Console → CocoScout → Statistics** (Users, Engagement for DAU/MAU
   and monthly returning users) **and Android vitals** (crashes, ANRs).
3. **When the server-side tracking ships, update the privacy answers** (both
   can change without a new build; App Store Connect asks you to publish the
   new answers):
   - App Store Connect → App Privacy → add **Usage Data → Product
     Interaction**: collected, linked to the user, not used for tracking,
     purpose **Analytics**.
   - Play Console → App content → Data safety → add **App activity → App
     interactions**: collected, not shared, purpose **Analytics**.
   - Then Claude updates `PrivacyInfo.xcprivacy` (it rides the next iOS
     build), `ios/app_store_submission.md` and
     `android/play_store_submission.md` so they keep matching.
   - The privacy policy already lists "Analytics services" among providers; it
     should also say we keep a record of how the app and site are used to
     improve them. Claude can draft that line for you to approve.
4. Pick where the numbers live: a new **App usage** page in superadmin, or a
   panel on the existing superadmin dashboard. (Superadmin only; nothing in
   the My nav or the app menu.)

### What Claude can build (after Tim picks)

1. **An `app_activity_days` table:** user_id, date, platform (ios/android),
   app version (nil = V1), nav generation; unique on user_id + date. Plus a
   small **`app_page_days`** rollup: date, platform, controller#action, count
   (no user_id, so "most used screens" stays aggregate).
2. **A concern next to `ActivityTracking`**, only for `turbo_native_app?`
   requests from a signed-in user: upsert today's row once a day per person
   (the same signed-cookie throttle, in a solid_queue job so requests stay
   fast), and bump the page counter for GET page loads. Demo users and
   impersonated sessions are skipped.
3. **The superadmin report:** app DAU/WAU/MAU by platform, versions in use
   (useful for knowing when V1 installs have died away), weekly retention by
   first app week, top 20 app pages, and app vs website share of active users.
4. **A one-time backfill** from `sessions.user_agent` so "first app day"
   starts from each person's first app sign-in, not from launch of the
   tracking.
5. Specs for the concern (web requests don't write rows; app requests write
   one per day) and the report queries.

About a day of work, server-only, so it can ship in an ordinary deploy without
touching either app build.

## Sources

- [PostHog free tier (Usercall, checked May 2026)](https://usercall.co/post/posthog-pricing)
- [TelemetryDeck pricing update, July 2026](https://telemetrydeck.com/blog/pricing-update-2026/)
- [Umami Cloud FAQ](https://docs.umami.is/docs/cloud/faq), [Umami Hobby limits (freetier.co)](https://freetier.co/directory/products/umami)
- [App Store Connect: manage app privacy](https://www.developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
- [App Store Connect: performance metrics](https://developer.apple.com/help/app-store-connect/reference/reporting/performance-metrics/)
- [App Store Connect Analytics 2026 update (stora.sh)](https://stora.sh/blog/2026-04-23-app-store-connect-analytics-100-new-metrics-guide)
- [Play Console statistics](https://support.google.com/googleplay/android-developer/answer/139628)
- [Analytics for web view apps (Median)](https://median.co/blog/app-analytics-for-webview-apps-what-you-can-cant-track)
- [GA4 events from a WebView (Google codelab)](https://codelabs.developers.google.com/codelabs/ga4f-event-tracking-webview)
