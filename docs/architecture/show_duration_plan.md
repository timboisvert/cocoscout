# Add Duration Field to Shows & Events

## Overview

Shows currently only have `date_and_time` (start time) with no end time or duration. Calendar sync hardcodes a 2-hour default. Adding a `duration_minutes` column is low difficulty, high value.

---

## Phase 1: Core Change (~1 hour)

### 1. Migration

```ruby
add_column :shows, :duration_minutes, :integer # nullable, optional
```

### 2. Model (`app/models/show.rb`)

- Add `ends_at` convenience method: `date_and_time + duration_minutes.minutes`
- Add `time_range_display` helper that returns `"7:00 PM – 9:00 PM"` (or just `"7:00 PM"` if no duration)
- Add `duration_hours` convenience method

### 3. Calendar Sync (highest value fix)

- `app/models/calendar_event.rb` — currently hardcodes `start + 2.hours` as end time
- `app/services/calendar_sync/google_service.rb` — uses the hardcoded value for Google Calendar API
- `app/services/calendar_sync/ical_service.rb` — uses it for iCal `DTSTART`/`DTEND`
- Replace with real `ends_at` when available, fall back to 2-hour default

### 4. Controllers (permit list + creation)

- `manage/shows_controller.rb` — add `duration_minutes` to permit list
- `manage/show_wizard_controller.rb` — capture duration during show creation
- `manage/contracts_controller.rb` — already has duration from space rental, pass it through to show creation

### 5. Factory + Specs

- Update `spec/factories/shows.rb` — add optional `duration_minutes` default
- Nothing breaks since the field is nullable

---

## Phase 2: Backfill Existing Data

### From Space Rentals

Shows linked to `SpaceRental` records can be backfilled automatically:

```ruby
Show.where.not(space_rental_id: nil).find_each do |show|
  rental = show.space_rental
  next unless rental

  duration = ((rental.ends_at - rental.starts_at) / 60).round
  show.update_column(:duration_minutes, duration)
end
```

### Default for Unlinked Shows

Optionally set a default (e.g., 120 minutes) for shows without a space rental:

```ruby
Show.where(space_rental_id: nil, duration_minutes: nil).update_all(duration_minutes: 120)
```

---

## Phase 3: UI Updates (~2-3 hours, can be gradual)

### Show Create/Edit Forms

- Add a duration `<select>` to the show wizard and edit forms
- Match the options from contract bookings: 1, 1.5, 2 (default), 3, 4–18 hours

### Views (~35 files, ~180 references)

All currently show start time only via `date_and_time.strftime(...)`. Update to use `time_range_display` helper. Key files:

| Area | Files | Priority |
|---|---|---|
| `app/views/manage/shows/` partials (`_show_row`, `_shows_list`, etc.) | 5 | High |
| `app/views/manage/productions/show.html.erb` | 1 | High |
| `app/views/my/` (user-facing calendar, show pages) | ~10 | High |
| `app/views/public/` (public show page) | 1 | Medium |
| `app/views/manage/` (other admin pages) | ~18 | Low |

### Mailers & SMS (6 touch points, optional)

- `app/mailers/show_mailer.rb`
- `app/mailers/advance_mailer.rb`
- `app/mailers/availability_mailer.rb`
- SMS templates in controllers

### JavaScript (1 file)

- Add duration selector to show creation Stimulus controller

### Seeds

- Update `lib/tasks/demo_seed.rake` — add `duration_minutes` to show creation calls

---

## Phase 4: Enhanced Conflict Detection (optional)

With `duration_minutes` on shows, the `SpaceRental#no_overlapping_rentals` validation can do proper range-based conflict detection against standalone shows (not just point-in-time checks).

```ruby
# Current: checks if show's date_and_time falls within rental window
# Enhanced: checks if show's full time range overlaps with rental window
conflicting_shows = Show
  .where(location_space_id: location_space_id, canceled: false)
  .where(space_rental_id: nil)
  .where.not(duration_minutes: nil)
  .where(
    "date_and_time < ? AND (date_and_time + (duration_minutes || 120) * interval '1 minute') > ?",
    ends_at, starts_at
  )
```

---

## Summary

| Phase | Effort | Impact |
|---|---|---|
| 1. Core (migration, model, calendar sync, controllers) | ~1 hour | High — fixes hardcoded 2-hour calendar events |
| 2. Backfill | ~15 min | Medium — populates existing data |
| 3. UI updates | ~2-3 hours | Medium — gradual, nothing breaks without it |
| 4. Conflict detection | ~30 min | Low — nice-to-have improvement |

**Total estimate: ~4-5 hours for full implementation, ~1 hour for the critical fix.**
