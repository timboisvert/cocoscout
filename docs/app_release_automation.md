# App release automation

Until V1.1, every app release meant Tim archiving in Xcode and uploading by
hand, and running `./gradlew bundleRelease` and dragging the bundle into the
Play Console. After the one-time steps below, Claude does both uploads, the
way Morning Line already works: iOS through Xcode Cloud, started by a git tag;
Android through Gradle Play Publisher, run on this Mac.

**The repo is public. No key, key file, password or token ever goes in git.**
Xcode Cloud signs with Apple's cloud-managed certificates (nothing of ours in
the repo). The Play service account's key, the upload keystore,
`keystore.properties` and `google-services.json` stay on Tim's Mac and in
1Password, all gitignored or outside the repo.

## How a release goes from now on

1. Claude bumps the version in the code: iOS `MARKETING_VERSION` in
   `ios/CocoScout.xcodeproj/project.pbxproj` (both configurations; the build
   number is left alone, Xcode Cloud sets it), Android `versionName` and
   `versionCode` (+1) in `android/app/build.gradle.kts`. Commits and pushes.
2. **iPhone:** Claude tags main and pushes the tag:
   `git tag ios-v1.2 && git push origin ios-v1.2`. Xcode Cloud archives,
   signs, uploads to App Store Connect and hands the build to the internal
   TestFlight group. Nothing for Tim yet.
3. **Android:** Claude runs, from `android/`,
   `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew publishReleaseBundle`.
   That builds, signs and uploads the bundle to **internal testing as a
   draft**. When Tim says it goes out, Claude sends it to Production review
   with `./gradlew publishReleaseBundle --track production --release-status completed`
   (or rolls out part way with `--release-status inProgress --user-fraction 0.2`).
   Then Claude tags the commit `android-v1.2` and pushes the tag, as a record.
4. **Tim's part:** try the TestFlight / internal-testing build on a phone,
   then in App Store Connect attach the build to the new version, fill in
   What's New and screenshots if they changed, and press Add for Review.
   Store listings, screenshots, privacy answers and anything Apple or Google
   asks in review stay his.

A second iPhone build of the same version is a new tag (`ios-v1.2-2`); the
build number goes up by itself. A failed Xcode Cloud run is re-run from App
Store Connect → Xcode Cloud, or with a new tag.

## iPhone: Xcode Cloud

What's in the repo:

- `ios/ci_scripts/ci_pre_xcodebuild.sh` sets the build number to the
  project's `CURRENT_PROJECT_VERSION` (6, V1.1's hand upload) plus Xcode
  Cloud's `CI_BUILD_NUMBER`, so the first cloud build is 7 and every one
  after is higher than the last. It edits only Xcode Cloud's throwaway clone.
  Raising the committed number later is fine; never lower it. The project has
  no `VERSIONING_SYSTEM` and a generated Info.plist, so the script rewrites
  the build setting instead of using agvtool as Morning Line does.
- `ios/CocoScout.xcodeproj/xcshareddata/xcschemes/CocoScout.xcscheme`: the
  CocoScout scheme, shared. Xcode Cloud only sees shared schemes in git;
  before this the scheme existed only on Tim's Mac. Archive uses Release,
  which signs with `CocoScout-Release.entitlements`. That file must keep Tap
  to Pay out until Apple grants it (`ios/tap_to_pay.md`); Xcode Cloud builds
  exactly what is committed, so nothing changes there.
- No `ci_post_clone.sh`: nothing to install. The two Swift packages
  (hotwire-native-ios, stripe-terminal-ios) are public and pinned by the
  committed `Package.resolved`, and the app needs no gitignored file to build.

### Tim's one-time steps (Xcode, about 15 minutes)

1. Pull main, open `ios/CocoScout.xcodeproj` in Xcode.
2. **Integrate → Xcode Cloud → Create Workflow…** (Xcode 15 and later,
   including 26.4; older guides say Product). Another way in: the Report
   navigator (⌘9) → **Cloud** tab → Get Started. If the item is greyed out,
   check Xcode → Settings → Accounts is signed in to the team, as Account
   Holder, Admin or App Manager. Pick the CocoScout product
   (com.cocoscout.app, team 3Y9EQJP24Y). If Xcode asks to create the product
   in App Store Connect, it already exists: pick it.
3. Xcode asks for access to the source: **Grant Access** to
   `github.com/timboisvert/cocoscout`. It opens GitHub to install Apple's "Xcode
   Cloud" GitHub app; give it access to that repository only. (The repo being
   public doesn't matter; Xcode Cloud reads it through that app and never
   needs a token of ours.)
4. In the workflow editor:
   - **General:** name it `Release`. Tick "Restrict editing" if offered.
   - **Environment:** Xcode "Latest Release", macOS "Latest Release". Leave
     "Clean" on.
   - **Start Conditions:** delete the default "Branch Changes" condition
     (the wizard only offers a branch, so this is an edit after saving:
     Integrate → Manage Workflows, or ⌘9 → Cloud → right-click → Edit
     Workflow). Add **Tag Changes** → **Custom Tags** → `ios-v`. Until it's
     changed, every push to main builds.
   - **Actions:** delete any default Build/Test actions. Add **Archive**,
     platform iOS, scheme **CocoScout**, Deployment Preparation **App Store
     Connect** (one choice only; the other, "TestFlight (Internal Testing
     Only)", can never go to review, and "None" uploads nothing).
   - **Post-Actions:** add **TestFlight Internal Testing**, artifact from the
     Archive action, group: your internal testers group (create one in App
     Store Connect → TestFlight → Internal Testing if there is none; Tim
     alone is enough).
   - Optional: **Post-Actions → Notify** by email on failure.
5. Save. Xcode Cloud doesn't build until a matching tag arrives.

Done 2026-10-29: workflow made, tag start condition, App Store Connect
upload, TestFlight internal post-action. Tested with `ios-v1.1` (before the
upload was switched on) and `ios-v1.1-2`, while 1.1 was still in review. App
Store Connect stops taking 1.1 builds once 1.1 is released, so the next tag
needs the version bumped first. Where to see it: Xcode's Report navigator
(⌘9) → Cloud, or Integrate → Manage Workflows.

Cost: the Apple Developer Program includes 25 compute hours a month; one
archive takes well under one.

## Android: Gradle Play Publisher

What's in the repo: the `com.github.triplet.play` plugin (Gradle Play
Publisher 4.1.1, the line that supports AGP 9) in `android/app/build.gradle.kts`.
It reads the service account key from
`~/.config/cocoscout/play-service-account.json` (outside the repo) or from
the `ANDROID_PUBLISHER_CREDENTIALS` environment variable. Without either,
`bundleRelease` and everything else build as before; only the publish tasks
fail. A bare `publishReleaseBundle` goes to **internal testing as a draft**,
so nothing reaches the public unless the command names `--track production`.

Signing doesn't change: Claude's upload runs on this Mac, with the upload key
and `keystore.properties` already here (both in 1Password too). No CI holds
them. Play's release notes, when wanted, go in
`android/app/src/main/play/release-notes/en-US/default.txt` (plain text, 500
characters; that file is fine in git). Claude never runs `publishListing` or
`publishApps`: those overwrite the store listing, which stays Tim's.

### Tim's one-time steps (Google Cloud and Play Console, about 15 minutes)

1. **Google Cloud console** (console.cloud.google.com), signed in as the
   Play developer account's owner: pick or create a project (e.g.
   `cocoscout-play`).
2. **APIs & Services → Library →** search "Google Play Android Developer
   API" → **Enable**.
3. **IAM & Admin → Service Accounts → Create service account**: name
   `play-publisher`. Skip the optional role and user-access steps (Play
   permissions are granted in Play Console, not here). Note its email,
   `play-publisher@<project>.iam.gserviceaccount.com`.
4. Open the service account → **Keys → Add key → Create new key → JSON**. A
   `.json` file downloads. It is a password: never into the repo, a chat, or
   a commit.
5. Save that file in 1Password (CocoScout, next to the upload key), then put
   it where the build looks for it:
   ```bash
   mkdir -p ~/.config/cocoscout && mv ~/Downloads/<the-file>.json ~/.config/cocoscout/play-service-account.json && chmod 600 ~/.config/cocoscout/play-service-account.json
   ```
   Delete any other copy left in Downloads.
6. **Play Console → Users and permissions → Invite new users**: the service
   account's email. Under **App permissions**, add CocoScout
   (com.cocoscout.app) with: Release apps to testing tracks, Release to
   production, exclude devices, and use Play App Signing; Manage testing
   tracks and edit tester lists. No account-level permissions. **Invite
   user**. (Google can take up to a day before the new account's uploads are
   accepted.)
7. Tell Claude it's done. Claude checks the key reads the app's listing
   (`./gradlew bootstrapListing` into a throwaway copy, nothing uploaded),
   and the first upload rides the next release.

If Tim would rather the key never sit on disk, Claude can run the upload as
`ANDROID_PUBLISHER_CREDENTIALS="$(op read 'op://<vault>/<item>/<file>')" ./gradlew publishReleaseBundle`
with the 1Password CLI, which asks Tim to approve each read.

## What stays Tim's

- App Store Connect: attaching the build to a version, What's New,
  screenshots, privacy answers, Add for Review, and replies to App Review.
  (A later step could give Claude an App Store Connect API key, kept outside
  the repo like the Play key, to submit for review too. Not set up.)
- Play Console: store listing, Data safety, anything in review, and saying
  when a build goes to production.
- Both: the accounts, keys and the people on them. Claude never creates
  accounts or keys.
