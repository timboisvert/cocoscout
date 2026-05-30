# Social Login Plan (Google, Apple, Facebook)

Status: **planned, not started** — the user is not ready to build this yet. Deferred
after Features 1 & 3 (profile-completion panel and staff-screen invites) shipped. This
is the largest remaining auth item because it adds a table, gems, three provider
integrations, and external account setup.

This doc has two halves:
1. **Current state** — an accurate inventory of how sign-up/login works today (from a
   full code review on 2026-05-29).
2. **The future** — the complete target feature set for sign-up/login, then the
   implementation detail for social login specifically.

---

## Part 1 — Current state of sign-up & login (as built today)

Hand-rolled auth on Rails 8 primitives. **No Devise, no OmniAuth.**

### Storage & session
- `User` uses `has_secure_password`. **`users.password_digest` is `NOT NULL`** — every
  user must have a password today. (This is *the* constraint that shapes social login:
  social-only users will be given a generated random password rather than relaxing this.)
- A `Session` table + a signed `session_id` cookie (`httponly`, `same_site: :lax`).
- `Authentication` concern: `require_authentication`, `resume_session`,
  `start_new_session_for(user)`, `terminate_session`, `after_authentication_url`.
- Password validations: length 8–72 + complexity (upper/lower/number/special), and they
  only run `if: password.present?`.

### Web flows (`AuthController`)
- **Signup** (`GET/POST /signup`): creates `User`, then finds-or-creates a linked
  `Person` (name defaults to email prefix), signs in, sends `AuthMailer.signup`,
  redirects to last-used dashboard (manage vs my) honoring `return_to`. Rate-limited
  10/10min. If the email already exists it re-renders `:signin` with a flag.
- **Signin** (`GET/POST /signin`): `User.authenticate_by`; back-fills a `Person` if one
  is somehow missing; session + dashboard redirect. Rate-limited 10/3min.
- **Signout** (`GET /signout`): `terminate_session`; remembers last-dashboard in an
  encrypted cookie across sign-outs.
- **Password reset** (`GET/POST /password` → `GET/POST /reset/:token`): Rails 8
  `generates_token_for(:password_reset)` (2-hour expiry, invalidated when the digest
  changes). **Account-enumeration-safe** (always shows "sent"). Rate-limited 5/10min.
- **Legacy `set_password/:token`**: older `User#invitation_token` flow, explicitly marked
  **deprecated** in favor of `PersonInvitation`. Kept for old links only.

### Invitations (the live invite path)
- `PersonInvitation` (token + optional org + optional talent_pool). Creation pattern
  (used by Staffing invites, talent pools, etc.): create `Person` + `User` (random
  secure password via `User.generate_secure_password`) + `PersonInvitation`, then email
  the link; on accept the user sets a password and joins the org/pool.
- **This is the precedent for social login's "user without a typed password" case** —
  the random-password trick already exists and is in production use.

### Mobile (Hotwire Native)
- `POST /api/v1/sessions` → returns a `generates_token_for(:api)` bearer token +
  `user_id`. `device_tokens` table (ios/android) for push. Separate from the web cookie
  session.

### Existing OAuth plumbing (not auth)
- A **hand-rolled Google OAuth flow for calendar sync**
  (`CalendarSync::GoogleService.authorization_url`, `my/calendar_sync#oauth_callback`,
  state param in session). Different OAuth client + scopes, NOT used for authentication —
  but it proves credentials/redirect handling work in this app.

### Notably absent today
- No social / OAuth **login**.
- No email verification/confirmation (password signups are trusted immediately).
- No 2FA, no account lockout / failed-attempt tracking.
- No "connected accounts" UI and no way to merge a social identity into an existing
  password account.

### Relevant `users` columns
`email_address` (unique), `password_digest` (NOT NULL), `password_reset_token`,
`invitation_token` + `invitation_sent_at` (legacy), `default_person_id`/`person_id`,
`last_seen_at`, `welcomed_at`, `welcomed_production_at`, notification prefs.

---

## Part 2 — The future: full sign-up & login feature set

Target end-state, grouped. Items marked **(new)** don't exist today; **(change)** adjusts
existing behavior; **(decision)** is a product call to make before building.

### A. Social sign-in/up — Google, Apple, Facebook **(new)** — the core of this work
The headline feature. Detail in Part 3 below.

### B. Account linking & management **(new)**
- "Connected accounts" section on the account page: list linked providers, link an
  additional provider, disconnect one.
- **Lock-out guard:** never let a user remove their last sign-in method — they must keep
  either a usable password or at least one linked provider.
- Smart handling when a social email matches an existing password account (auto-link only
  when the provider reports the email **verified**).

### C. Unified entry points **(change)**
- Today `/signup` and `/signin` partially cross-render each other (the "user exists" path
  renders `:signin`). Rework so all four paths — password, Google, Apple, Facebook —
  share one consistent layout with the social buttons beside the email form.

### D. Provider edge cases that force behavior **(new)**
- **Apple:** name returned only on first auth; email may be a private relay → key on
  `[provider, uid]`, fall back to email-prefix names.
- **Facebook:** needs app review for the `email` scope; some accounts have no email →
  may need a "confirm your email" step before completing signup.

### E. Decisions to make before/while building **(decision)**
- **Email verification for password signups** — we have none today. Social logins arrive
  pre-verified; password signups don't. Decide whether to add verification so the two
  paths are consistent. *Current lean: leave as-is for now to keep this focused.*
- **Native mobile social login** — the iOS app would need native Sign in with Apple /
  Google SDKs. **This plan covers the Rails web app only.**
- **2FA / lockout** — out of scope unless explicitly wanted.

---

## Part 3 — Social login implementation detail

## Current auth (what we're extending)

(See Part 1 for the full picture; the key facts the implementation leans on:)
- Custom auth: `User` + `has_secure_password` + `Session` table + signed cookie.
- `password_digest` is NOT NULL → social-only users get a generated random password
  (the `PersonInvitation` flow already does exactly this).
- `Authentication` concern gives us `start_new_session_for(user)`.
- A separate hand-rolled Google OAuth (calendar sync) exists but is not reused here.

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
