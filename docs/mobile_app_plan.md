# Mobile App Plan: Hotwire Native with Strada

Build iOS and Android apps using Hotwire Native (Turbo Native + Strada) that wrap the existing Talent Dashboard. This reuses your Rails views while adding native push notifications and UI components.

## Why Hotwire Native

- Reuses 100% of existing `/my` views - no duplication
- Style consistency guaranteed (same Tailwind CSS renders)
- Single codebase for features - add once to Rails, works everywhere
- Native shell handles auth, push tokens, navigation
- AI-friendly - most work is in Rails, minimal Swift/Kotlin

## Features (MVP)

- View upcoming shows with role assignments
- Submit availability (yes/no/maybe)
- Native push notifications for new shows, messages, requests
- View and reply to messages
- Open requests (sign-ups, questionnaires, auditions)
- Profile management

---

## Phase 1: Rails Preparation

### 1. Add Native Detection Helpers

In `app/controllers/application_controller.rb`:

```ruby
helper_method :turbo_native_app?

def turbo_native_app?
  request.user_agent.to_s.include?("Turbo Native")
end
```

Conditionally hide web-only elements (main nav, footer) when native.

### 2. Create Native-Optimized Layout

Create `app/views/layouts/native.html.erb`:
- Slim layout without top nav/sidebar
- Include Strada JavaScript bridge
- Keep Turbo + Stimulus imports

### 3. Build Minimal API

Create `app/controllers/api/v1/` with:

| Controller | Purpose |
|------------|---------|
| `api_controller.rb` | Base class with token auth concern |
| `sessions_controller.rb` | Token-based login for initial auth |
| `push_tokens_controller.rb` | Register APNs/FCM device tokens |

Use `authenticate_with_http_token` for API authentication.

### 4. Add DeviceToken Model

```bash
rails g model DeviceToken user:references token:string platform:string
```

Fields:
- `user_id` - belongs_to User
- `token` - device push token (unique index)
- `platform` - "ios" or "android"

### 5. Integrate Push Service

Options:
- `rpush` gem (self-hosted)
- `aws-sdk-sns` (AWS SNS)

Create `PushNotificationService` that:
- Sends to registered device tokens
- Hooks into existing `UserNotificationsChannel` patterns

---

## Phase 2: iOS App (Swift)

### 6. Create Xcode Project

Dependencies:
- `turbo-ios` Swift package (github.com/hotwired/turbo-ios)
- `strada-ios` Swift package

Configure `SceneDelegate` to load `https://cocoscout.com/my` as root.

### 7. Configure Navigation

Create path configuration JSON mapping URLs → presentation styles:
- **Modal**: `/my/messages/new`, `/profile/edit`
- **Push navigation**: drill-down paths
- **Tab bar**: Shows, Messages, Requests, Profile

### 8. Implement Strada Components

- Native nav bar with title from `<title>` tag
- Pull-to-refresh triggers Turbo reload
- Native share sheet for show/profile sharing
- Native image picker for headshot uploads

### 9. Push Notification Setup

- Register for remote notifications in `AppDelegate`
- Send token to `POST /api/v1/push_tokens`
- Handle notification tap → navigate to relevant path

---

## Phase 3: Android App (Kotlin)

### 10. Create Android Studio Project

Dependencies:
- `turbo-android`
- `strada-android`

Configure `MainActivity` with Turbo session and root URL.

### 11. Configure Navigation

Same path rules as iOS:
- Bottom navigation for main tabs
- Fragment-based navigation stack

### 12. Implement Strada Components

Mirror iOS implementations:
- Native toolbar
- Pull-to-refresh
- Share sheet

### 13. Push Notification Setup

- Firebase Cloud Messaging integration
- Register token with API

---

## Phase 4: Polish & Release

### 14. Path Configuration

Create `public/turbo/path-configuration.json`:
- Define modal vs push navigation paths
- Define native feature access requirements

### 15. Style Adjustments

- Use `turbo_native_app?` to hide redundant UI
- Adjust touch targets for mobile (48px minimum)
- Test headshot uploads via native picker

### 16. App Store Prep

- App icons & splash screens
- Privacy policy, terms of service pages
- TestFlight (iOS) / Internal testing track (Android)

---

## Verification Checklist

- [ ] Login flow works in iOS Simulator and Android Emulator
- [ ] Push notification delivery end-to-end
- [ ] Availability submission (yes/no/maybe taps)
- [ ] Message sending and real-time receipt via ActionCable
- [ ] Strada nav bar shows correct titles on navigation

---

## Key Decisions

| Decision | Choice | Reasoning |
|----------|--------|-----------|
| Framework | Hotwire Native | Reuses existing views, no API needed for most features, guaranteed style match |
| Push notifications | Native (APNs/FCM) | Users need alerts when app is closed |
| UI components | Strada | Native nav/UI elements make the app feel less "webview-y" |
| API scope | Minimal | Only auth tokens and push registration; all other data via HTML views |

---

## Resources

- [Turbo Native iOS](https://github.com/hotwired/turbo-ios)
- [Turbo Native Android](https://github.com/hotwired/turbo-android)
- [Strada iOS](https://github.com/hotwired/strada-ios)
- [Strada Android](https://github.com/hotwired/strada-android)
- [Hotwire Native Documentation](https://native.hotwired.dev/)
