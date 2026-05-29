# Social Login Plan (Google, Apple, Facebook)

Status: **planned, not started** — deferred while Features 1 & 3 (profile-completion
panel and staff-screen invites) ship first. This is the largest of the three because
it adds a table, gems, three provider integrations, and external account setup.

## Current auth (what we're extending)

- Custom auth: `User` with `has_secure_password` + a `Session` table + a signed
  `session_id` cookie. No Devise / no OmniAuth today.
- `Authentication` concern provides `start_new_session_for(user)`, `resume_session`,
  `require_authentication`, etc.
- `AuthController` handles `/signup`, `/signin`, `/password`, `/set_password/:token`.
- Password validations (length + complexity) only run `if: password.present?`, so a
  user can exist without a typed password — but `has_secure_password` still requires a
  password at create time unless told otherwise. We sidestep this by giving social-only
  users a random secure password (see below).
- There is already a **hand-rolled Google OAuth flow for calendar sync**
  (`CalendarSync::GoogleService.authorization_url`, `my/calendar_sync#oauth_callback`).
  That's a *different* OAuth client/scope set and is NOT reused for authentication, but
  it proves the credential plumbing and redirect handling work in this app.

## Approach

Use **OmniAuth** with maintained provider strategies rather than hand-rolling three
flows. Apple's JWT client-secret and Facebook's review/edge cases are far safer via
the gems.

Gems:
- `omniauth`
- `omniauth-google-oauth2`
- `omniauth-apple`
- `omniauth-facebook`
- `omniauth-rails_csrf_protection` (required; provider links must be POST)

## Data model

New table `authentications`:

| column      | type     | notes                                   |
|-------------|----------|-----------------------------------------|
| user_id     | bigint   | FK → users                              |
| provider    | string   | "google_oauth2" / "apple" / "facebook"  |
| uid         | string   | provider's stable user id               |
| email       | string   | email reported by provider              |
| name        | string   | name reported by provider               |
| timestamps  |          |                                         |

- Unique index on `[provider, uid]`.
- `User has_many :authentications, dependent: :destroy`.
- Social-only users get a random password via `User.generate_secure_password`
  (same trick the invitation flow already uses) so we never touch
  `has_secure_password`'s create-time presence validation. Lowest-risk path.

## Callback flow

`OmniauthCallbacksController` (unauthenticated access):

1. `auth = request.env["omniauth.auth"]` → provider, uid, info.email, info.name.
2. Find `Authentication` by `[provider, uid]` → sign that user in.
3. Else find `User` by **verified** provider email → create the `Authentication`
   row (link) + sign in. Only auto-link when the provider marks the email verified
   (Google/Facebook do; Apple does on first auth).
4. Else create `User` (random pw) + `Person` (mirror the signup flow's person
   creation) + `Authentication` → sign in.
5. `start_new_session_for(user)` and redirect (respect `return_to_after_authenticating`).

Routes:
- `GET /auth/:provider` — OmniAuth request phase (middleware-handled).
- `GET|POST /auth/:provider/callback → omniauth_callbacks#create`.
- `GET /auth/failure → omniauth_callbacks#failure`.
- No collision: existing auth routes are `/signin`, `/signup`, etc. — not under `/auth/*`.

UI: "Continue with Google / Apple / Facebook" buttons on the signin + signup pages,
rendered as `button_to "/auth/<provider>", method: :post`.

## Provider-specific notes

- **Apple**: needs a Services ID + Team ID + Key ID + `.p8` private key (omniauth-apple
  builds the client-secret JWT). Returns the user's name only on the *first* auth, and
  email may be an Apple private-relay address — rely on `[provider, uid]`, fall back to
  email prefix for name.
- **Facebook**: needs a Meta app and **app review for the `email` permission**.
- **Google**: can add an authorized redirect URI to the existing project or create a
  dedicated web client → client id/secret.

## External setup required (the real blockers)

These must be provided before the integration can be finished:
- Google OAuth web client id/secret (+ redirect URI registered).
- Apple Services ID, Team ID, Key ID, and `.p8` key.
- Facebook app id/secret with `email` permission approved.

Store all in Rails encrypted credentials / ENV; read them in `config/initializers/omniauth.rb`.

## iOS app

The `CocoScout iOS` app would need **native Sign in with Apple** (and native Google/FB
SDKs) as a separate integration. This plan covers the **Rails web app only**.

## Files to add/change

- `Gemfile` — the OmniAuth gems above.
- `config/initializers/omniauth.rb` — provider config from credentials/ENV.
- Migration — `authentications` table.
- `app/models/authentication.rb` + `User has_many :authentications`.
- `app/controllers/omniauth_callbacks_controller.rb`.
- `config/routes.rb` — callback + failure routes.
- `app/views/auth/signin` + `signup` — provider buttons.
- Optional v1.1: "Connected accounts" management (list/disconnect) on the account page.

## Suggested build order once credentials land

1. Scaffold gems + `authentications` table + `Authentication` model + initializer stub.
2. Wire Google end-to-end first (simplest, credentials likely easiest).
3. Add Facebook, then Apple (most setup).
4. Add account-linking management UI (optional).
