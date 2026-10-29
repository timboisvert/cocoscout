# V1.1 release checklist

Everything V1.1 needs to go out, in order. The code is finished on branch
`v1.1` (2026-10-21; `docs/production_mode_v2_plan.md` §10 says what was
built). What's left is release work, and most of it is yours.

## The rule

V1.1 is never deployed until **both** V1 app reviews pass (iOS build 5,
submitted 2026-10-15, approved 2026-10-28; Android 1.0 live on Google Play since 2026-10-20). Both passed: the gate is open. V1 installs read `path-configuration.json`
and `native_menu`, which V1.1 leaves untouched; V1.1 builds say "nav 2" in
their user agent and read `nav-2/path-configuration.json`, so the server
side can go out before the V1.1 apps and V1 phones won't notice.

## 1. Before merging (yours)

- [ ] Look it over on your localhost (it serves `v1.1`): production mode on
      a phone, the one Messages inbox (pills, the For chips, opening a
      thread from the other organization asks first), the People Picker on
      the casting board and vacancies, Notifications.
- [ ] Look over "Get the app" (built 2026-10-28): the section at the bottom
      of `/`, `/for-performers` and `/for-producers`, the footer badges,
      `/app` on a desktop (badges + QR) and on a phone (straight to its
      store), the one-time nudge on My Home from a phone's browser, and the
      two links in every email's footer. The screenshots are the V1 store
      ones ("My Calendar"); recapture from the simulator once V1.1 is the
      app, so they say "Home".
- [x] App versions (2026-10-28): iOS 1.1 (build 6); Android 1.1 (build 4,
      after the internal-testing Tap to Pay build 3, which never reached
      Production; this one carries Tap to Pay on Android too). The
      user-agent marker reads the version, nothing else depends on it.

## 2. Merge and deploy the server (yours; Claude can merge on your word)

- [x] Merge `refs/heads/v1.1` into `main` (2026-10-28) (no conflicts expected; `main`
      hasn't moved on the same files, but check).
- [x] Deploy (2026-10-28). The deploy runs the three Notifications migrations,
      `AddLastModeToUsers`, the mailing-list migrations, and the two payout
      notice migrations (`AddNoticeStampsToPayoutBatches`: `funded_at` and
      `completion_notified_at`; `AddPayoutRunLifecycleTemplates`: the
      submitted, funded, completed and partly-paid templates, so no rake
      seed to run). All additive, nullable, no backfill.
- [x] After the deploy, nothing to run in `kamal console`: no backfills.
      (The payee-details console block from `docs/after_v1.md` ran
      separately: 104 payees synced.)
- [ ] Watch the first hour: the mail icon's count is now one number in both
      modes, and every automated notice is a Notification (vacancy and
      questionnaire invitations, the Tap to Pay launch moved last).

## 2b. Mailing lists (yours: Mailgun, DNS and 1Password)

Sending to followers stays off in production until these are done: the send
button says "Sending to followers isn't switched on yet."

**Trying it out first (Tim, 2026-10-28):** follower email can share
cocoscout.com's sending domain under a CocoScout-wide cap of 2,000 a month
(`FOLLOWERS_MONTHLY_CAP` changes it), switched on with `FOLLOWERS_SENDING: on`
under `env.clear` in `config/deploy.yml`. **Not on Mailgun's free plan:** it
is a hard 100 emails a day for everything, so one email to 150 followers
would stop sign-in and ticket mail until midnight. Move to Basic ($15 a
month, 10,000, no daily cap) first, then switch it on. The steps below are
for the separate `news.cocoscout.com` domain, which needs Foundation 50k
(docs/follower_email_pricing.md).

- [ ] Mailgun: move off the free tier (3,000 a month for all of CocoScout).
      Pro includes 500 follower emails a month per organization for now, a
      hard stop (Tim, 2026-10-23).
- [ ] Mailgun: add the sending domain `news.cocoscout.com`, and its SPF, DKIM
      and MX records in Route 53 (the zone for cocoscout.com).
- [ ] Mailgun → that domain → Webhooks: point Delivered, Permanent failure,
      Spam complaints and Unsubscribes at `https://www.cocoscout.com/webhooks/mailgun`.
- [ ] 1Password (CocoScoutProductionPasswords): add `MAILGUN_WEBHOOK_SIGNING_KEY`
      (Mailgun → Sending → Webhooks → signing key).
- [ ] `.kamal/secrets`: add `MAILGUN_WEBHOOK_SIGNING_KEY` to the fetch list and
      an extract line; `config/deploy.yml`: add it under `env.secret`, and
      `FOLLOWERS_MAIL_DOMAIN: news.cocoscout.com` under `env.clear`. Only after
      the 1Password item exists, or the deploy fails.

## 3. The apps (yours: Apple and Google only take builds from you)

- [ ] iOS: archive and upload the V1.1 build from `ios/` (the project at
      `ios/CocoScout.xcodeproj`, scheme CocoScout). What's new: production
      mode, the organization band, Messages and Notifications in the nav bar,
      the new menu. **New screenshots:** `ios/app_store_screenshots/v1.1/`
      (6.9" iPhone, taken 2026-10-28 on production: Home, the menu, the Door
      admitting someone, the production-mode menu, production Home, the show
      sheet, the casting board). Claude can't reach App Store Connect, so
      you upload them. Android's listing can use the same seven.
- [ ] Both stores' privacy answers, now that the server counts app usage
      (`docs/mobile_app_analytics.md`, "What only Tim can do" step 3): App
      Store Connect → App Privacy → Usage Data → Product Interaction
      (linked, not tracking, Analytics); Play Console → Data safety → App
      activity → App interactions (collected, not shared, Analytics). The
      V1.1 build's `PrivacyInfo.xcprivacy` already says so.
- [ ] Android: `./gradlew bundleRelease` from `android/` (Android Studio's
      JDK), upload to the Play Console. The release build's `BASE_URL` is
      production; debug is localhost.
- [ ] Both: the apps bundle `public/hotwire-native/nav-2/path-configuration.json`
      (Android as an asset, iOS fetches it), so a server deploy can change
      page rules later without a new build.

## 4. Once V1.1 is the minimum build (later, yours to call)

- [ ] Add `/manage/*` to the universal links / app links (plan §8), so a
      production-mode link opens the app. Not before: a V1 phone would open
      `/manage` in the app with no production mode.
- [ ] Retire the V1 `path-configuration.json` and `native_menu` only when no
      V1 installs are left (the user agent says which generation each phone
      runs).

## After V1.1 (not in it)

- Native upgrades behind the same markup: the action sheet via the Menu
  bridge, nav-bar Save/Next, the native share sheet (Tim, 2026-10-21: after
  V1.1).
- V1.2: Tap to Pay (`ios/tap_to_pay.md`), on Apple's clock.
