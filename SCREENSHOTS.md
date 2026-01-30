# Screenshot List for /new Producers Page

All screenshots should be taken at **1440x900** resolution. Use the demo organization and log in as `demo@demo.cocoscout.com`.

---

## 1. Auditions (3 screenshots)

- [ ] **1-1: Audition Form Builder**
  - Page: `/manage/productions/[ID]/audition_cycles/[ID]/edit`
  - Show: Questions section, cuts/files section, deadline fields
  - Scroll to show the richest part of the form

- [ ] **1-2: Submissions List**
  - Page: `/manage/productions/[ID]/audition_cycles/[ID]/audition_requests`
  - Show: Grid of submissions with headshots, names, timestamps
  - Ideally some have ratings (stars), show filtering controls

- [ ] **1-3: Submission Detail**
  - Page: Click into one submission from the list
  - Show: Headshot, video player, answers to questions

---

## 2. Casting (2 screenshots)

- [ ] **2-1: Casting Table**
  - Page: `/manage/productions/[ID]/casting_table`
  - Show: Role columns with performers assigned, talent pool on side
  - Best if multiple roles are filled

- [ ] **2-2: Org Casting Grid**
  - Page: `/manage/casting`
  - Show: Multi-production casting overview with multiple shows

---

## 3. Scheduling (3 screenshots)

- [ ] **3-1: Shows List**
  - Page: `/manage/productions/[ID]/shows`
  - Show: List of upcoming shows with dates, times, locations, cast counts

- [ ] **3-2: Show Detail / Call List**
  - Page: `/manage/productions/[ID]/shows/[ID]`
  - Show: Individual show with cast list, roles assigned

- [ ] **3-3: Availability Grid**
  - Page: `/manage/productions/[ID]/availability`
  - Show: Grid showing performer availability across shows

---

## 4. Payouts (2 screenshots)

- [ ] **4-1: Money Dashboard**
  - Page: `/manage/productions/[ID]/money`
  - Show: Overview with totals, recent shows with payout status

- [ ] **4-2: Payout Scheme Setup**
  - Page: `/manage/productions/[ID]/money/payout_schemes/[ID]` or create new
  - Show: Scheme configuration (per-show rates, role amounts)

---

## 5. Accounting (2 screenshots)

- [ ] **5-1: Financial Overview**
  - Page: `/manage/productions/[ID]/money`
  - Show: Revenue/expense summary section, charts if visible

- [ ] **5-2: Show Financials Detail**
  - Page: Click into a show's financials
  - Show: Per-show P&L breakdown, revenue, expenses

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

**Total: 12 screenshots** across 5 features
