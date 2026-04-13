# Mobile App Plan: Hotwire Native

Build iOS and Android apps using [Hotwire Native](https://native.hotwired.dev/) that wrap the entire Talent Dashboard (`/my`). This reuses all existing Rails views while adding native push notifications and Bridge Components for key interactions.

> **Status (April 2026):** No implementation started. All items below are planned work.

## Why Hotwire Native

- Reuses 100% of existing `/my` views — no duplication
- Style consistency guaranteed (same Tailwind CSS renders in a native WebView)
- Single codebase for features — add once to Rails, works everywhere
- Native shell handles auth, push tokens, navigation animations
- Bridge Components (formerly Strada) are now built into Hotwire Native — no separate dependency
- AI-friendly — most work is in Rails, minimal Swift/Kotlin
- Instant updates — deploy to Rails and both apps see changes without app store review

## Features (MVP)

The native apps wrap the entire `/my` dashboard. All 20 existing controllers are available from day one since they render as HTML inside the native WebView:

| Area | Controller | What it does |
|------|-----------|--------------|
| Dashboard | `dashboard` | Central hub: profiles, groups, productions, calendar |
| Shows | `shows` | Browse shows, view details, role assignments, filters |
| Availability | `availability` | Submit yes/no/maybe for shows and auditions |
| Messages | `messages` | Inbox with threads, rich text, reactions, polls |
| Direct Messages | `direct_messages` | Person-to-person private messages |
| Production Messages | `production_messages` | Messages to production teams |
| Open Requests | `open_requests` | Consolidated availability, sign-ups, questionnaires |
| Sign-ups | `sign_ups` | Self-service registration for shows |
| Auditions | `auditions` | View audition cycles, accept/decline slots |
| Submit Audition | `submit_audition_request` | Apply for auditions with availability + questions |
| Questionnaires | `questionnaires` | Fill out production questionnaires |
| Productions | `productions` | View productions, agreements, details |
| Profiles | `profiles` | Multi-profile management (create, edit, switch) |
| Groups | `groups` | Create and manage talent groups |
| Courses | `courses` | Browse course listings and sessions |
| Course Registrations | `course_registrations` | Register and check out for courses |
| Payments | `payments` | Payment history, payout setup (Venmo/Zelle) |
| Posts | `posts` | Community discussion posts per production |
| Shoutouts | `shoutouts` | Give/receive peer recognition |
| Calendar Sync | `calendar_sync` | Connect Google Calendar for show sync |

**Native-only additions:**
- Native push notifications (APNs/FCM) for new shows, messages, requests, vacancies
- Bridge Components for native nav bar, pull-to-refresh, form submit buttons
- Native share sheet for show/profile sharing
- Native image picker for headshot uploads

---

## Phase 1: Rails Preparation

### 1. Add Native Detection Helper

In `app/controllers/application_controller.rb`:

```ruby
helper_method :turbo_native_app?

def turbo_native_app?
  request.user_agent.to_s.include?("Turbo Native")
end
```

Conditionally hide web-only elements (main nav, footer) when running inside the native shell.

### 2. Create Native-Optimized Layout

Create `app/views/layouts/native.html.erb`:
- Slim layout without top nav/sidebar
- Include `@hotwired/hotwire-native-bridge` for Bridge Components
- Keep Turbo, Stimulus, and ActionCable imports

### 3. Install Hotwire Native Bridge (Web)

Pin the Bridge Component JavaScript library via importmap:

```bash
bin/importmap pin @hotwired/hotwire-native-bridge
```

This enables web-side Bridge Components (Stimulus controllers that extend `BridgeComponent`) to communicate with native counterparts.

### 4. Build Minimal API

Create `app/controllers/api/v1/` with:

| Controller | Purpose |
|------------|---------|
| `base_controller.rb` | Token auth using `generates_token_for` |
| `sessions_controller.rb` | Exchange email/password for API token |
| `push_tokens_controller.rb` | Register/deregister APNs/FCM device tokens |

**Auth approach** — aligns with the existing custom auth system (`has_secure_password` + Session model + `Current.user`). For the API:

```ruby
# app/models/user.rb
generates_token_for :api, expires_in: 30.days

# app/controllers/api/v1/base_controller.rb
class Api::V1::BaseController < ActionController::API
  before_action :authenticate_api_user!

  private

  def authenticate_api_user!
    authenticate_with_http_token do |token, _options|
      Current.user = User.find_by_token_for(:api, token)
    end or render json: { error: "Unauthorized" }, status: :unauthorized
  end
end

# app/controllers/api/v1/sessions_controller.rb
class Api::V1::SessionsController < Api::V1::BaseController
  skip_before_action :authenticate_api_user!, only: :create

  def create
    user = User.find_by(email_address: params[:email])
    if user&.authenticate(params[:password])
      render json: { token: user.generate_token_for(:api), user_id: user.id }
    else
      render json: { error: "Invalid credentials" }, status: :unauthorized
    end
  end
end
```

### 5. Add DeviceToken Model

```bash
rails g model DeviceToken user:references token:string platform:string
```

Fields:
- `user_id` — belongs_to User
- `token` — device push token (unique index on `[token, platform]`)
- `platform` — `"ios"` or `"android"`

Add `has_many :device_tokens` to User model.

### 6. Integrate Push Notifications with rpush

Add to Gemfile:

```ruby
gem "rpush"
```

Then:

```bash
bundle install
rails rpush:generate
rails db:migrate
```

Create `app/services/push_notification_service.rb`:
- Wraps rpush to send to APNs (iOS) and FCM (Android)
- Hooks into existing `UserNotificationsChannel` broadcast points
- When a broadcast goes out via ActionCable, also fire a push notification to device tokens for users not currently connected

**Existing ActionCable channels that should trigger push notifications:**

| Channel | Broadcast | Push trigger |
|---------|-----------|--------------|
| `UserNotificationsChannel` | `broadcast_new_message` | New message in subscribed thread |
| `UserNotificationsChannel` | `broadcast_unread_count` | Badge count update |
| `UserInboxChannel` | `broadcast_new_message` | New thread in inbox |

Push notifications supplement ActionCable — ActionCable handles real-time updates when the app is in the foreground (WebSocket works through the native WebView), while push notifications reach users when the app is backgrounded or closed.

---

## Phase 2: iOS App (Swift)

### 7. Create Xcode Project

Single dependency:
- [`hotwire-native-ios`](https://github.com/hotwired/hotwire-native-ios) Swift package (v1.2.2+)

This includes everything — navigation, WebView management, and Bridge Components. No separate packages needed.

Requirements: iOS 14+, Swift 5.3+

Configure `SceneDelegate` to load `https://cocoscout.com/my` as root URL.

### 8. Configure Navigation

Set up tab-based navigation:

| Tab | Icon | Root path |
|-----|------|-----------|
| Dashboard | `house` | `/my` |
| Shows | `calendar` | `/my/shows` |
| Messages | `envelope` | `/my/messages` |
| Requests | `bell` | `/my/requests` |
| Profile | `person` | `/my/profiles` |

Use path configuration (shared JSON, see Phase 4) to control push vs modal presentation per URL pattern.

### 9. Implement Bridge Components

Bridge Components replace the old "Strada components" concept. Each has a web half (Stimulus controller extending `BridgeComponent`) and a native half (Swift class):

| Component | Web → Native | Purpose |
|-----------|-------------|---------|
| `NavBarButton` | Form submit text | Native nav bar button triggers web form submit |
| `Menu` | Menu items | Web dialog → native `UIActionSheet` |
| `Form` | Submit action | Native submit button in toolbar for forms |

Built-in behaviors (no Bridge Component needed):
- Pull-to-refresh (configured via path configuration `pull_to_refresh_enabled`)
- Native back/forward navigation
- Page titles from `<title>` tag

### 10. Push Notification Setup

- Register for remote notifications in `AppDelegate`
- On token receipt, `POST /api/v1/push_tokens` with `{ token:, platform: "ios" }`
- Handle notification tap → extract path from payload → navigate via Hotwire Native navigator
- Badge count synced from `UserNotificationsChannel` unread count

---

## Phase 3: Android App (Kotlin)

### 11. Create Android Studio Project

Single dependency:
- [`hotwire-native-android`](https://github.com/hotwired/hotwire-native-android) (v1.2.7+)
  - `dev.hotwire.core`
  - `dev.hotwire.navigation-fragments`

Requirements: Android SDK 28+, Kotlin

Configure `MainActivity` with Hotwire session and root URL `https://cocoscout.com/my`.

### 12. Configure Navigation

Same tab structure as iOS:
- Bottom navigation bar with 5 tabs (Dashboard, Shows, Messages, Requests, Profile)
- Fragment-based navigation stack per tab
- Shared path configuration JSON controls presentation styles

### 13. Implement Bridge Components

Mirror iOS Bridge Component implementations:
- Native toolbar with `NavBarButton` component
- `Menu` component → native `BottomSheetDialog`
- `Form` component → native submit in toolbar

### 14. Push Notification Setup

- Firebase Cloud Messaging (FCM) integration
- On token receipt, `POST /api/v1/push_tokens` with `{ token:, platform: "android" }`
- Handle notification tap → deep link to relevant path

---

## Phase 4: Path Configuration & Polish

### 15. Create Path Configuration

Create `public/hotwire-native/path-configuration.json` — served from the Rails app so it can be updated without app store submissions:

```json
{
  "settings": {
    "tabs": [
      { "title": "Dashboard", "path": "/my", "icon": "house" },
      { "title": "Shows", "path": "/my/shows", "icon": "calendar" },
      { "title": "Messages", "path": "/my/messages", "icon": "envelope" },
      { "title": "Requests", "path": "/my/requests", "icon": "bell" },
      { "title": "Profile", "path": "/my/profiles", "icon": "person" }
    ]
  },
  "rules": [
    {
      "patterns": [".*"],
      "properties": {
        "context": "default",
        "pull_to_refresh_enabled": true
      }
    },
    {
      "patterns": ["/new$", "/edit$"],
      "properties": {
        "context": "modal",
        "pull_to_refresh_enabled": false
      }
    },
    {
      "patterns": ["/my/messages/[0-9]+/reply"],
      "properties": {
        "context": "modal",
        "pull_to_refresh_enabled": false
      }
    },
    {
      "patterns": ["/my/sign_ups/.*/form", "/my/questionnaires/.*/form"],
      "properties": {
        "context": "modal",
        "pull_to_refresh_enabled": false
      }
    }
  ]
}
```

Key properties:
- `context` — `"default"` (push) or `"modal"` (presented modally)
- `presentation` — `"default"`, `"push"`, `"pop"`, `"replace"`, `"replace_root"`, `"none"`
- `pull_to_refresh_enabled` — boolean
- iOS-specific: `view_controller`, `modal_style` (`"large"`, `"medium"`, `"full"`)
- Android-specific: `uri`, `fallback_uri`, `title`

### 16. Style Adjustments

- Use `turbo_native_app?` to hide redundant UI (top nav, footer, breadcrumbs)
- Adjust touch targets for mobile (48px minimum)
- Test headshot uploads via native image picker
- Ensure ActionCable WebSocket connects properly through the native WebView

### 17. App Store Prep

- App icons & splash screens
- Privacy policy, terms of service pages
- TestFlight (iOS) / Internal testing track (Android)
- Configure rpush with APNs certificates and FCM server key

---

## Verification Checklist

- [ ] Login flow works in iOS Simulator and Android Emulator
- [ ] API token exchange (`POST /api/v1/sessions`) works
- [ ] Push notification delivery end-to-end (rpush → APNs/FCM → device)
- [ ] Device token registration and deregistration
- [ ] All `/my` pages render correctly in native WebView
- [ ] Tab navigation between Dashboard, Shows, Messages, Requests, Profile
- [ ] Availability submission (yes/no/maybe) via web view
- [ ] Message sending and real-time receipt via ActionCable (WebSocket through WebView)
- [ ] Push notification received when app is backgrounded
- [ ] Notification tap navigates to correct screen
- [ ] Bridge Component nav bar shows correct titles on navigation
- [ ] Modal presentation for new/edit forms
- [ ] Pull-to-refresh on list pages
- [ ] Badge count on Messages tab synced with unread count

---

## Key Decisions

| Decision | Choice | Reasoning |
|----------|--------|-----------|
| Framework | Hotwire Native | Reuses all existing views, no API needed for content, guaranteed style match |
| Push notifications | rpush (self-hosted) | Fits Kamal deployment, handles both APNs and FCM, no external service dependency |
| Native UI | Bridge Components | Built into Hotwire Native — native nav/UI elements make the app feel less "webview-y" |
| API scope | Minimal | Only token auth + push token registration; all content delivered as HTML via WebView |
| MVP scope | Entire `/my` dashboard | All 20 controllers wrapped from day one — it's all just HTML rendering, no extra cost |
| Auth pattern | `generates_token_for` | Aligns with existing custom auth (`has_secure_password` + Session model), no new auth system needed |

---

## Resources

- [Hotwire Native Documentation](https://native.hotwired.dev/)
- [Hotwire Native iOS](https://github.com/hotwired/hotwire-native-ios) (Swift, v1.2.2)
- [Hotwire Native Android](https://github.com/hotwired/hotwire-native-android) (Kotlin, v1.2.7)
- [Hotwire Native Bridge (Web JS)](https://github.com/hotwired/hotwire-native-bridge)
- [Bridge Components Overview](https://native.hotwired.dev/overview/bridge-components)
- [Path Configuration Reference](https://native.hotwired.dev/reference/path-configuration)
- [rpush](https://github.com/rpush/rpush)
