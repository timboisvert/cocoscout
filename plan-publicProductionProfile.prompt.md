Plan: Public Production Profile

TL;DR

Add support for a public production profile (public pages + show detail pages) and public-key management for `Production`, reusing the existing `PublicKeyService` and `public_profiles` patterns used for `Person` and `Group`.

This will allow unique, shareable public URLs for productions and show pages at `/:public_key` and `/:public_key/shows/:id`.

DECISIONS (already chosen):
- Public-key namespace: Option A — single namespace (Person + Group + Production) so public_key values are globally unique. PublicKeyService will check Person, Group and Production.
- Public show URLs: `/:public_key/shows/:id` (consistent with existing public profile routing)
- Default: `public_profile_enabled` defaults to ON for productions (publicly visible by default)

OBJECTIVE

Create a public-facing profile page for a Production that can be reached with a stable, unique public key and a public pages surface that shows poster, basic production information, upcoming shows (each show gets its own public page), short cast listings and venue/address + map placeholder. Reuse existing publicProfiles patterns and PublicKeyService.

IMPLEMENTATION PLAN (copy-ready)

1) Database migration (productions)

- New migration file: `db/migrate/XXXXXXXXXXXXXX_add_public_profile_to_productions.rb`
- Columns to add on `productions` table:
  - `public_key :string` (unique index)
  - `public_key_changed_at :datetime`
  - `old_keys :text` (nullable — JSON array of previous keys — parity with Person/Group)
  - `public_profile_enabled :boolean`, default: true, null: false

- Add unique index on `public_key`.

2) Model enhancements — `app/models/production.rb`

- Validations:
  - Uniqueness for `public_key` (allow blank when no key)
  - Format validation: `/\A[a-z0-9][a-z0-9\-]{2,29}\z/` (same as Person/Group)
  - `public_key_not_reserved` to consult `config/reserved_public_keys.yml`
  - `public_key_change_frequency` to prevent frequent changes (copy logic from Person)

- Callbacks:
  - `before_validation :generate_public_key, on: :create` → Use `PublicKeyService.generate(name)`
  - `before_save :track_public_key_change` (push previous key into `old_keys` JSON array and set `public_key_changed_at`)

- Helper methods to copy:
  - `generate_public_key`
  - `downcase_public_key`
  - `update_public_key(new_key)`
  - `track_public_key_change`

3) PublicKeyService update

- Update `app/services/public_key_service.rb` to include Production checks when generating / validating keys:
  - Ensure uniqueness against Person, Group, and Production
  - Ensure reserved list consulted (config/reserved_public_keys.yml)

4) Routing & Controller updates

- `config/routes.rb` — keep existing public routes and add show route:
  - `get '/:public_key', to: 'public_profiles#show', as: 'public_profile', constraints: { public_key: /[a-z0-9][a-z0-9\-]{2,29}/ }` (already exists)
  - Add `get '/:public_key/shows/:id', to: 'public_profiles#show_production_show', as: 'public_profile_show', constraints: { public_key: /[a-z0-9][a-z0-9\-]{2,29}/ }`

- `app/controllers/public_profiles_controller.rb` — extend `find_entity` to include Production:
  - Try `Person.find_by(public_key: key)` → `Group.find_by(public_key: key)` → `Production.find_by(public_key: key)`
  - Support `old_keys` fallback for Production (like Person/Group) and redirect with 301 to new key
  - If found Production and `public_profile_enabled` is false → render `public_profiles/not_found` status 404
  - `show` should render `public_profiles/production` for productions, and `shoutouts` behavior remains same for Person/Group
  - Add `show_production_show` action to render a public-facing details page for a show `/:public_key/shows/:id` — includes cast assignments and details

5) Views & manage UI

- New public views (mirroring person/group structure):
  - `app/views/public_profiles/production.html.erb` — main public production profile page (hero/poster, description, upcoming shows grid with links to `/:public_key/shows/:id`, cast highlight, venue/address section and share/copy URL UI). See draft template provided separately.

  - `app/views/public_profiles/show_production_show.html.erb` — public-facing show detail page (title, full date/time, venue, description, full cast listing with links to person public profiles)

- Manage UI (reuse `groups/edit.html.erb` patterns):
  - `app/views/manage/productions/edit.html.erb` — add UI for toggling `public_profile_enabled` and controls to change `public_key` (use the same `shared/copy_url` partial for the public URL), and add a clear description to explain public visibility
  - `app/views/manage/productions/show.html.erb` — add a “View Public Profile” link when enabled (target _blank)

6) Tests

- Model specs: `spec/models/production_public_key_spec.rb` — format validation, uniqueness, reserved keys, ability to update and track old keys

- System specs: `spec/system/public_profiles/production_spec.rb` (pattern same as `person_shoutouts_spec.rb` & `group_shoutouts_spec.rb`)
  - visiting `public_profile_path(production.public_key)` renders the public profile
  - disabled profile returns 404
  - old keys redirect to new key (301)
  - `/:public_key/shows/:id` renders the show detail as expected

- Integration tests for `PublicKeyService` behavior with Production

IMPLEMENTATION NOTES / OPEN QUESTIONS

- Namespace collisions: We use single namespace (Option A) and ensure `PublicKeyService` checks Person, Group and Production.
- Public show routing: `/:public_key/shows/:id` is adopted — simple and consistent.
- Defaults: `public_profile_enabled` default = `true` (public by default).

DOCUMENTATION + PLACEMENT

- Draft public page template: `app/views/public_profiles/production.html.erb` (a copy-ready draft will be provided separately)
- Implementation plan & notes file location in repo: `docs/feature-plans/public-production-profile.md`

NEXT STEPS (when you’re ready for implementation)

If you want me to implement now, I’ll:
1. Add DB migration + run tests for schema
2. Update `Production` model with callbacks/validations
3. Update `PublicKeyService` uniqueness checks to include Production
4. Update `PublicProfilesController#find_entity` and add show_production_show action
5. Add the two public views and manage UI changes
6. Add model & system tests, run test suite and fix issues

---

Notes: This plan follows the existing person/group public-profile patterns and reuses `PublicKeyService` to keep behavior consistent across entities. When you’re ready I can implement the migrations, model updates, controllers and views in small PR-sized commits.
