# Screenshot List for /new Producers Page

All screenshots should be taken at **1440x900** resolution. Use the demo organization and log in as `demo@demo.cocoscout.com`.

**Save to:** `app/assets/images/screenshots/`

---

## 1. Auditions (3 screenshots)

Folder: `screenshots/auditions/`

- [ ] **1-form-builder.png**
  - Page: `/manage/signups/auditions/[PRODUCTION_ID]/[CYCLE_ID]/form`
  - Show: Questions section, cuts/files section, deadline fields
  - Scroll to show the richest part of the form

- [ ] **2-submissions-list.png**
  - Page: `/manage/signups/auditions/[PRODUCTION_ID]/[CYCLE_ID]/requests`
  - Show: Grid of submissions with headshots, names, timestamps
  - Ideally some have ratings (stars), show filtering controls

- [ ] **3-submission-detail.png**
  - Page: `/manage/signups/auditions/[PRODUCTION_ID]/[CYCLE_ID]/requests/[REQUEST_ID]`
  - Show: Headshot, video player, answers to questions

---

## 2. Casting (3 screenshots)

Folder: `screenshots/casting/`

- [ ] **1-casting-table.png**
  - Page: `/manage/casting/tables/[TABLE_ID]`
  - Show: Role columns with performers assigned, talent pool on side
  - Best if multiple roles are filled

- [ ] **2-notifications.png**
  - Page: (User to add)
  - Show: (User to add)

- [ ] **3-org-grid.png**
  - Page: `/manage/casting`
  - Show: Multi-production casting overview with multiple shows

---

## 3. Scheduling (3 screenshots)

Folder: `screenshots/scheduling/`

- [ ] **1-shows-list.png**
  - Page: `/manage/shows/[PRODUCTION_ID]`
  - Show: List of upcoming shows with dates, times, locations, cast counts

- [ ] **2-show-detail.png**
  - Page: `/manage/shows/[PRODUCTION_ID]/[SHOW_ID]`
  - Show: Individual show with cast list, roles assigned

- [ ] **3-availability-grid.png**
  - Page: `/manage/casting/[PRODUCTION_ID]/availability`
  - Show: Grid showing performer availability across shows

---

## 4. Accounting (2 screenshots)

Folder: `screenshots/accounting/`

- [ ] **1-financial-overview.png**
  - Page: `/manage/money/financials/[PRODUCTION_ID]`
  - Show: Revenue/expense summary section, charts if visible

- [ ] **2-show-financials.png**
  - Page: `/manage/money/shows/[SHOW_ID]/financials`
  - Show: Per-show P&L breakdown, revenue, expenses

---

## 5. Payouts (2 screenshots)

Folder: `screenshots/payouts/`

- [ ] **1-dashboard.png**
  - Page: `/manage/money/payouts/[PRODUCTION_ID]`
  - Show: Overview with totals, recent shows with payout status

- [ ] **2-scheme-setup.png**
  - Page: `/manage/money/schemes/[SCHEME_ID]` or `/manage/money/schemes/new`
  - Show: Scheme configuration (per-show rates, role amounts)

---

## Tips

- **Browser**: Use Chrome/Safari in a clean window (no bookmarks bar)
- **Resolution**: 1440x900 or 1920x1080 (will be resized)
- **Data**: Make sure there's enough demo data to look busy but not overwhelming
- **Scroll position**: Frame to show the most visually interesting part
- **Hover states**: Don't capture mid-hover
- **Sidebars**: Include the sidebar - it shows context

---

## Quick IDs

Run in Rails console to get production IDs:
```ruby
Production.joins(:organization)
  .where(organizations: { name: "Starlight Community Theater (Demo Organization)" })
  .pluck(:name, :id)
```

---

**Total: 13 screenshots** across 5 features
