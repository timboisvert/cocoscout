# Production Mode in the App (V1.1, was V2): difficulty assessment and plan

*Read-only audit of `/manage`, 2026-10-14. No code was changed for it.*

**Status: locked 2026-10-14. Renamed 2026-10-19: this is V1.1 (was V2); Tap to Pay is V1.2 (was V1.1).** Built on a branch while V1 is in review, never deployed until both app reviews pass; Tap to Pay waits on Apple's publishing entitlement and ships whenever that lands. Navigation mockups: https://claude.ai/artifact/CNaAubdaxfkbdn3ST59LwG. Plan page: https://claude.ai/artifact/J5PCo4RYJ3Q9G4PUCR7s1R.

**Scores**
- **1** = already close; mostly reflows inside the native layout.
- **2** = real create/edit work that needs mobile patterns: sheets, card rows, sticky actions, and drill-in sections instead of tabs.
- **3** = the screen's value is seeing a lot at once, or it depends on drag-and-drop. It needs a different interaction model on a phone.

**Priority**
- **H** = producers need it away from a desk (day-of-show, a call-out, settling a night).
- **M** = needed sometimes.
- **L** = setup or desk work.

---

## 0. Release plan

Nothing in this plan is built this week.

1. **V1, now.** Finish the app and ship it with today's features.
   - Include the must-ship items from the V1 triage in §8.
   - Most of those fixes are server-side (views and `path-configuration.json`), so any that miss launch can follow without an app release.
   - Keep today's `path-configuration.json` safe for V1 for as long as V1 installs are around. V1 builds will always read it.
2. **V1.1, next (was V2).** Production mode and the rest of this plan, built on a branch while V1 is in review and never deployed until both app reviews pass.
   - Give each app build its own path-config address (`AppConfig.swift:24`) and a version marker in the user agent, so V1.1 server changes can't reach V1 installs.
   - Enter/exit production mode, the floating nav, the organization switcher.
   - Production features on mobile web and the app together, in the §7/§8 order.
   - The invisible plumbing (0a) can start now.
3. **V1.2, whenever Apple grants the publishing entitlement (was V1.1).** Tap to Pay, out quickly, before or after V1.1.

## 0a. What's locked (navigation and modes)

- **One site, one login, one app.** `/my` and `/manage` stay; no subdomains.
- **One mobile experience.** Mobile web and the app get the same screens and features; the app differs only in its frame.
- **The everyday side has no name.** You enter and exit production mode.
- **The switch is a menu link,** a CocoScout-pink bar (`bg-pink-500`, white text) at the **bottom** of the account menu (moved from the top 2026-10-20: it's used rarely and shouldn't be in the way), never an always-visible control. The menu is the same in both modes. On a phone it sits under Work the door, near the bottom of the menu sheet.
- **Profile, account settings and superadmin** are account-menu items, not dashboards.
- **Top left is the CocoScout logo in both modes** (2026-10-20, was "logo or band"), a little smaller than today, with the Messages and Notifications icons to its right on the same line. In production mode a soft pink band under them names the organization with its ▾ and says "Production mode" in plain words, with no icon beside those words anywhere.
- **The organization name always has a single ▾,** on every plan.
  - Several organizations: the list, with your role and each one's plan, then settings and New organization.
  - One organization: production settings, organization settings, plan and billing, a locked "Add a production" (Producer plan allows one) and New organization.
- **The desktop sidebar floats:** inset, rounded, soft shadow; in production mode its edge and shadow pick up a faint pink.
- **Pro with several productions:** "Productions" moves from the account menu into the nav with a count.
- **Producer plan (free):** Pro modules stay in the nav with today's grey padlock (`shared/pro_marker`, `kind: :lock`), and today's plan meter sits under them.
- **Team access as today:** non-managers see the free modules and no Pro heading; audition reviewers see Sign-ups only.
- **Contract people aren't production mode's audience** (2026-10-17, `docs/contract_people_plan.md`): contractors and the people they bring never enter the Production Dashboard; their dates, sales, comps and contract are on My. Production mode is for the organization and its in-house production teams.
- **The address decides the mode.** A link into `/manage` switches by itself and says so in a soft pink notice with an Exit button (`shared/button`, secondary, small); the app opens in the last mode used.
- **Messages and Notifications are universal** (2026-10-20): the bell is the only way into Notifications (no nav item, no "My"), and the list holds everything, read ones included; a mail icon and a bell, each with a count, at the top of the desktop panel, in the phone's top bar, and in the app's native nav bar, the same in both modes. Neither nav lists them. The mail icon opens one Messages list in either mode, which pulls the unified inbox (§8, deferred) into V1.1; until the data merge it can open My Messages with production threads included.
- **Crossing modes from a notification:** opening one whose page lives in the other mode asks first, in a pink-header modal ("Open in production mode?", Switch and open, Don't ask again).
- **Counts:** only Tasks carries a count in the nav; Productions keeps its quantity.
- **The app:**
  - the same menu, drawn natively;
  - a soft pink strip with the organization under the nav bar in production mode;
  - the floating Coco button stays, with **no badge** (Tim, 2026-10-20): the mail and bell icons carry the counts (`MenuButton.swift` drops its count);
  - the menu sheet: a plain outlined card at the top with your picture, name and email, Profile and Settings under them and the close button in its corner (not pink: pink bars are things to do); in production mode a soft pink row under it names the organization (no pill); Work the door (black) and the Enter/Exit bar (CocoScout pink, white text) pinned to the bottom of the sheet; nothing CocoScout pink anywhere (Tim, 2026-10-20);
  - the menu tiles' counts use the same pink (`MenuViewController.swift`, today `Color.red`).

**Decided 2026-10-20** (Tim chose 4, 5 and 6; 1–3 are the recommendations, his to change):
1. "Start producing" is website-only; the apps never pitch producing.
2. Superadmin is web-only (it opens in the browser from the app); impersonating inside a V1.1 app shows a "You're impersonating · Stop" banner.
3. Course instructors take attendance from My (their course on My Courses), never production mode.
4. Labels everywhere: "Home" and "Shows & Events" (no "My Calendar" / "My Shows" in V1.1 menus).
5. The switch notice keeps its Exit button.
6. Pro isn't sold in the apps: upgrading opens the website's billing page.

Found while building the mockups (existing, not fixed): production Home hides an open vacancy's Review button on desktop until hover (`md:hidden md:group-hover:block`), and Sign-ups' Waitlists card shows an info icon because `queue-list` is missing from `shared/_module_header_icon`.

## 1. Bottom line

1. **The production dashboard is much closer to phone-ready than its density suggests.**
   - Of about 170 distinct screens, roughly **105 score a 1**, **58 score a 2**, and only **6 score a 3**.
   - That is because of recent phone work: `shared/slim_list` rows that wrap, `settings_layout`'s phone `<select>`, `module_header`'s folded actions, `wizard_steps`, `show_row`, `month_calendar`'s day list, the casting board's mobile assign sheet, the Pay People accordion, and the payout card layouts.
   - Ticketing and Money are already largely phone-aware.
2. **The difficulty is concentrated in six 3s.** Every one is a grid (people × shows / days / sessions / questions):
   - Staffing → Scheduling (week builder)
   - Casting → Casting Tables (batch-cast grid)
   - Casting → org-wide Availability matrix
   - Courses → Attendance (students × sessions)
   - Ticketing → Notification settings matrix (low priority)
   - Contacts → Questionnaire responses table (person × question; low priority)

   None of these should be squeezed onto a phone. Each needs a **pivot**: one show, one day, one person or one session at a time, with the rest one tap away.
3. **The real cost is cross-cutting, not per-screen.**
   - About **205 hand-rolled modals** across 110 manage views.
   - **23 hover-only reveals** across manage views (plus explanations that only exist in `title=` tooltips). On iPhone these are invisible: Tailwind v4 only applies `hover:` on devices that can hover, so `opacity-0 group-hover:opacity-100` never shows.
   - **14 wizards**, plus many tabbed edit pages.
   - Fixing these with **about 12 shared components** fixes most of the 2s at once.
4. **Before any screen can come in, the shell needs work.**
   - `/manage` is currently sent out to Safari.
   - The Manage controllers hard-code the full web layout.
   - The native menu only knows about Talent mode.

## 1a. Ground rule: one mobile experience

Everything in this plan is built **for phones, not for the app**. Mobile Safari and the app get the same screens, components and features. The app differs only in its **frame**.

**Rules**
- Phone layouts are gated by **screen width** (Tailwind `sm:` / `md:`), never by `turbo_native_app?`.
- `turbo_native_app?` is only for the frame:
  - hiding web navigation and titles that the native nav bar shows
  - bridge hooks
  - push prompts
  - things only the phone can do (Tap to Pay, the native scanner)
- A native piece is a **progressive upgrade of the same action**: same items, same order, same result, and a web version that works in mobile Safari.
  - ⋯ menu: web sheet on mobile web → native action sheet in the app.
  - Sharing: Web Share or copy → native share sheet.
  - Exports: download → QuickLook.
  - Some flows: web sheet → native modal presentation.
- Production mode uses the same `production_nav_sections` in both places. The enter/exit link sits at the top of the account menu on every surface; the four existing dashboard switchers (including the one in `shared/navigation/_mobile_grid_nav`) are retired.
- Every phase is checked at phone width in **both** mobile Safari and the app.

**Where the code stands today:** the existing app-only branches already follow this rule:
- native nav bar titles
- push prompts
- account links shown as rows because the app hides the sidebar
- the Door's native scanner and Tap to Pay

One deliberate exception needs revisiting for V1.1: the talent dashboard hides "Producing your own shows?" in the app (`my/dashboard/index.html.erb:56`), because Pro is sold on the web.

---

## 2. Phase 0: shell and plumbing (required before any screen)

| Item | What exists today | What V1.1 needs |
|---|---|---|
| **Switching modes** (see the market study, *Dual persona mode switching*) | Four different dashboard switchers on the web; the app's menu is talent only. | **No always-visible switcher.** **Decided (option A):** everyday CocoScout has no name at all (no "Talent Dashboard"), and an "Enter production mode" / "Exit production mode" link sits at the top of the account menu on desktop, mobile web and the app, drawn from one list the server sends. Alternatives considered: Personal/Producing; you vs. your organizations; "My CocoScout"; a named workspace such as "Production Office". Talent and Performing are ruled out because they leave out staff, contractors and students. Only people with production access see it; talent-only users get a quiet "Start producing". The top left shows context: the organization switcher plus a "Production mode" label in production mode; otherwise just the CocoScout mark. Profile, account and superadmin become account-menu items. The mode follows the address (`/my` vs `/manage`): links from the other mode switch automatically and announce it. The app opens in the last mode used, stored on the user. One inbox at both message paths. In the app, a `replace_root` rule on both mode home pages. |
| **Organization / production context** | Org and production are chosen in the session (`manage_controller.rb#set_current_organization`), so they already carry over into the WebView. | An org switcher in the menu's pink person card (the "Producing for: Stars & Garters ▾" pattern). Production selection stays in-page. |
| **Layout** | `Manage::ManageController` hard-codes `layout "application"` (`manage_controller.rb:11`). That layout's native branch is missing `shared/native/bridge` and `bridge--form`, so on Manage pages the native menu, push and nav-bar Save would not work. | Use `resolve_layout` (→ `layouts/native`) for Manage, or add the bridge partial and `bridge--form` to the application layout's native branch. |
| **Path configuration** | `^/manage` → `open_in: safari`. Generic `/new$`, `/edit$` and `/edit/` modal rules. | Remove the Safari rule. Add Manage-specific rules: <br>• Wizard steps after the first (`/wizard/`, `/new/…`, `/setup/`) must stay in the modal; today only step 1 matches `/new$`. <br>• Tabbed edit pages that should *not* be modals: `staffing/staff/:id/edit`, `ticketing/shows/:id/edit/sales`, `casting/tables/:id/edit/members`. <br>• `open_in: document` for CSV, print and PDF routes (guest list, door list, roster, reports CSV, W-9/1099, signed contracts). |
| **Universal links** | `apple_app_site_associations_controller.rb` lists only `/my`, `/door`, `/profile`, `/claim`, `/vacancy`. Its comment says "Manage and checkout stay in Safari". | Add `/manage/*`, so producer emails (call-outs, sign-ups, payouts) open in the app. Ship this together with the path-config change, or the links open the app and then bounce to Safari. |
| **Hover sweep** | 23 hover-only reveals in manage views (`opacity-0 group-hover:opacity-100`, `hidden group-hover:block`), plus explanations that only exist in `title=` tooltips. | One sweep that adopts the existing touch-safe pattern `block md:hidden md:group-hover:block` (already used at `manage/home:258`, `show_row:709`), or a visible ⋯ menu. The same bug is **already live in V1** on a talent page; see §6. |
| **Native exports** | CSV links, `window.print`, inline PDFs. | Route them to QuickLook or the share sheet (the `DocumentPresenter` that already exists, plus path rules). |
| **Stripe-hosted flows** | Connect onboarding, payout funding setup, Checkout and Billing Portal all redirect to Stripe. | An in-app browser session that returns by universal link. **Product decision:** whether buying a CocoScout subscription from inside an iOS app is acceptable under App Store payment rules, or whether billing should be hidden or link out in the app. |

---

## 3. Section scorecard

| Section | Overall | Mobile priority | Hardest screen(s) | Already phone-ready |
|---|---|---|---|---|
| Home | **1** | H | none | Calendar already has a phone agenda list |
| Messages | **1.5** | H | Compose (2-step modal, 1,443-line controller) | Thread and row partials already ship in `/my/messages` |
| Shows & Events | **1.5** | H | Show detail (826 lines, ~8 modals, day-of hub); calendars (7-column grid) | `show_row`, show edit's phone tab select, show wizard |
| Casting | **2.5** | H | **Casting Tables grid (3)**, **org Availability matrix (3)**; casting board (2) | Board has a phone assign sheet; per-show and per-person availability modals already exist |
| Sign-ups & Auditions (+ Questionnaires) | **2** | H (sign-up roster, voting in the audition room) | Sign-up slot **assign** (drag is the only way to place someone in a slot; every row action is hover-only); sign-up form settings (1,075-line form with 6 tabs) | Phone vote bar on both review screens; casting-select bottom sheet; tap-to-schedule auditions; question reorder supports touch |
| Courses | **2** | H (show, attendance, add student) | **Attendance (3)**; course show | Wizard, money pages |
| Documents | **2** | M | Editor (`100vh` card with an inner scroll; the keyboard hides Save) | Reader already ships in `/my/documents` |
| Contacts | **1** | **H** | none. Cheap, high-payoff work: contact rows with call/text/email | Filter bar folds up on phones |
| Ticketing | **1.5** | H | Show page (show-night hub, unpaginated guest list); tier editor; notifications matrix (3, low priority) | Most pages; `/my/ticket_sales` reuses the same partials in the app |
| Staffing | **2** | H | **Scheduling (3)**; Pay People (2) | Hub, availability, timesheets, wizard; Pay already uses accordion cards on phones |
| Money | **1.4** | H | Show payouts (15+ modals, buried main action); settlement worksheet (modals on top of a modal) | Slim lists, payee cards, payout-run detail |
| Contracts | **2** | M–H | Contract detail (6 modals per payment row, 10-item kebab menu); deal financials step | List pages, wizard shell, contractor pages |
| Reports | **1–2** | M | Wide reports (Ticket Buyers has 11 columns) | One shared template, so one component fixes all 10 |
| Settings & admin (production edit, org settings, team, billing, locations) | **2** | L | Production edit (9 tabs with no phone menu; team management relies on hover) | Org settings already uses `settings_layout` |

---

## 4. Page by page

### Home: overall 1
| Page | Score | Pri | On a phone |
|---|---|---|---|
| `/manage` home | 1 | H | Agenda first, with a "Needs attention" stack on top (vacancies, sign-ups to review, unpaid payouts, hours to approve). |
| `/manage/productions/:id` production dashboard | 1 | H | Fix the hover-only "Review" button (`productions/show:285`). Same "Needs attention" stack. |
| `/manage/productions` index | 1 | M | Fine as is. |

### Messages: overall 1.5
| Page | Score | Pri | On a phone |
|---|---|---|---|
| Inbox (`messages#index`) | 2 | H | Search in the nav bar; filters in a sheet. |
| Compose (`shared/_compose_message_modal`) | 2 | H | Full-screen sheet: recipient type → **People Picker** → body, with Send in the nav bar. |
| Thread / production thread | 1 | H | Already the shipped `/my` partials. |

### Shows & Events: overall 1.5
| Page | Score | Pri | On a phone |
|---|---|---|---|
| Show lists (org and production) | 1 | H | Keep `show_row`. Filters go in a sheet with chips for active filters. The headshot strip opens a "Cast for this show" sheet; today names only appear in tooltips. |
| Calendars (org and production) | 2 | M | Reuse home's agenda list, or a week strip with a day list. Today it's a `min-w-[640px]` grid that scrolls sideways. |
| **Show detail** | 2 | **H** | Sticky bottom bar with the day-of actions (Attendance, Contact cast, Manage cast). Edit, Duplicate, Cancel and Transfer go in a ⋯ action sheet. Money and Tickets sections collapse. |
| Attendance | 1 | H | A full page instead of an auto-opening modal: search, big toggles, sticky "Add walk-in". |
| Show edit (8 tabs) | 2 | M | Section list you drill into; one Save in the nav bar. |
| Cancel / transfer / time change | 1 | M | Fine as is. |
| New show wizard | 1 | M | Wizard shell. |

### Casting: overall 2.5
| Page | Score | Pri | On a phone |
|---|---|---|---|
| `/manage/casting` org index; production index | 1 | H | Pin an "Action needed" group. Tapping the row opens the board; today headshots jump to the person's page. |
| **Casting board** (`show_cast`) | 2 | **H** | Already has a phone path: Assign buttons open a bottom sheet. Make the slot list *the* board: tap a filled slot for an action sheet (Can't make it / Replace / Move to… / Remove). Add a sticky "4/6 cast · Notify" bar, with Notify as a full-screen sheet. Gaps to close are listed in §6. |
| Vacancy (`vacancies#show`) | 2 | **H** | **People Picker** sorted by availability, then a sticky "Send invites" button. Resend becomes visible; today it's hover-only. |
| Production availability matrix | 2 | M | Default to a list of shows with ✓/✗/– counts. Tapping a show pushes the existing show modal as a page; add a People tab. |
| **Org availability matrix** | **3** | M–H | Per-show list grouped by production. Tapping a show opens Available / No response / Unavailable tabs (already built in `org_availability/_show_modal`). An action sheet replaces the side popup that JS places next to the row. |
| **Casting Tables grid** | **3** | L–M | **Show pager**: one show at a time, roles → tap a slot → picker showing each member's running count. Optional per-member checklist: "Pick Alex's shows". |
| Casting tables list, wizard, summary, edit lists | 1 | L | Wizard shell. |
| Casting settings → Roles | 2 | L–M | Explicit Reorder mode. `role_order` currently blocks scrolling and posts a reorder on every tap; see §6. |
| Per-show casting settings / show roles modal | 2 | L | Give it a real route and push it as a screen. Reorder with ↑/↓; today it's HTML5 drag only, with no touch support. |
| Talent pools | 2 | M | Tapping a tile opens an action sheet. Add uses the People Picker. Remove/Revoke are hover-only today. |
| Roles index | 1 | L | Fine as is. |

### Sign-ups & Auditions (and Questionnaires): overall 2
| Page | Score | Pri | On a phone |
|---|---|---|---|
| Sign-ups hub, production sign-ups, form lists, auditions hub | 1 | H | Auditions' Form / Requests / Sessions / Casting nav becomes a segmented control. |
| **Sign-up form show** (live roster) | 2 | **H** | Day-of line-up first; date pills or swipe between events. Tap a row → action sheet (Move / Remove / Profile); today Move and Remove are ~24px links. QR goes through the native share sheet. |
| **Sign-up assign** (queue → slots) | 2 | M–H | **Slot Picker sheet**: tap a queued person, then pick a slot. Today only HTML5 drag works, with no touch support. Return / Auto-assign / Remove get a visible ⋯ instead of hover-only. Sticky "Auto-assign all". |
| Sign-up form edit (question builder) | 2 | L | **Question Builder**: full-screen editor, reorder mode (touch reorder already exists). |
| Sign-up form settings (6 tabs) / sign-up wizard | 2 | L–M | Section list; Save or Next in the nav bar; one **Offset input** for the ~10 hand-built days/hours/minutes triplets. |
| Confirm slot/event changes, preview, print list | 1 | L | Before/After toggle; print list via `open_in: document`. Preview should render the talent partials; today it's a hand copy. |
| **Audition requests list** | 2 | **H** | Compact rows with vote chips; sort/filter sheet ("not voted by me", "most yes"); Select mode for bulk archive. |
| **Audition review + vote** (request and session) | 1 | **H** | Phone vote bar already built. Add swipe, "next one I haven't voted on", prev/next within the session, and haptics. |
| **Session run-sheet** (`audition_sessions#show`) | 1 | **H** | Tapping a row opens the review card; prev/next is already scoped to the session. |
| Sessions list | 2 | M | Modals become sheets. |
| Schedule auditions | 2 | M–H | Already tap-based (`audition_assign`). Picker becomes a full-screen sheet; Remove is visible. |
| Casting decisions / casting select | 2 | M–H | Phone bottom sheet already exists; polish it and reuse the review card. Notify flow: review → edit email → send. |
| Audition form, settings, wizard | 2 | L | Question Builder; section list; wizard shell. |
| Questionnaires: index, responses, response | 1 | M | Fine as is. |
| Questionnaire show / form | 2 | M / L | People Picker for invites; Question Builder. |
| **Questionnaire responses table** | **3** | L | Don't port it. Per-question summary plus the existing per-response view. |

### Courses: overall 2
| Page | Score | Pri | On a phone |
|---|---|---|---|
| Course list | 1 | M | Compact rows, stats as a 2-up strip. |
| **Course show** | 2 | **H** | ⋯ menu for course actions. "Mark completed" and "Reopen" are missing from the phone layout today. The registrant "Contact" button is invisible on touch. Registration link goes through the native share sheet. |
| Add student | 1 | **H** | Walk-in at the door; "Add" in the nav bar. |
| **Attendance** | **3** | **H** | **Session checklist**: pick a session (default today), then big tap rows and a running count. *Catch:* the controller replaces each student's whole attendance list, so it needs a one-session endpoint. |
| Course edit (5 tabs) / wizard | 2 | L–M | Section list; session fields stack in one column. |
| Payout / payout run / money / settings / questionnaire / change notice | 1–2 | L–M | Payee **money rows**; failure reasons shown inline instead of only in tooltips. |

### Documents: overall 2
| Page | Score | Pri | On a phone |
|---|---|---|---|
| Lists, new, show | 1 | M | Reuse the shipped `my/documents/show` reader. |
| **Editor** | 2 | L–M | Keyboard-aware full-screen editor sized with `dvh`, toolbar above the keyboard, Save in the nav bar. |
| Sharing modal | 2 | M | Full-screen sheet; native picker for permission. |

### Contacts: overall 1
| Page | Score | Pri | On a phone |
|---|---|---|---|
| **Directory** | 1 | **H** | Default to the list (tiles are the default today). **Contact row** with call / text / email / message. Search in the nav bar. |
| Person | 1 | **H** | Phone becomes a `tel:` / `sms:` link (plain text today). Action-button row. |
| Group | 1 | M | Member list using contact rows. |
| Invite person | 2 | M | Invite link through the native share sheet. |

### Ticketing: overall 1.5
| Page | Score | Pri | On a phone |
|---|---|---|---|
| Ticketing dashboard | 1 | H | "Tonight" card first, with an **Open Door** button; KPI tiles as 2×2. |
| Shows list, production page, links, change notice, visibility | 1 | M | Fine as is; the action list moves into a ⋯ menu. |
| **Show page** | 2 | **H** | Sticky header with status and **Open Door** (hand off to the existing `/door/:id`; don't rebuild check-in). Comps and "Sold elsewhere" become sheets with steppers; "Sold elsewhere" breaks at 390px today. Guest list is search-first and paginated. |
| **Orders / order detail / refund** | 1 | **H** | Sticky search plus infinite scroll; order sheet with a bottom action bar (Resend / Refund / Move / contact buyer). |
| Move tickets | 2 | M | A real 3-step flow instead of reloads. |
| Production ticket settings / per-date edit (tier editor) | 2 | L–M | Tier cards, each opening an edit sheet; reorder mode (▲▼ already exists). |
| Passes, deals, products, taxes, balance | 1–2 | L | Pass form is long; the rest is fine. |
| Ticketing settings → **Notifications matrix** | **3** | L | One row per email kind, tapping into a recipient checklist sheet. |

### Staffing: overall 2
| Page | Score | Pri | On a phone |
|---|---|---|---|
| Hub / roster | 1 | **H** | "Needs attention" card at the top. Call-out alert rows get **Find cover**, which opens the Assign sheet for that shift. |
| **Scheduling** | **3** | **H** (cover, fill, notify) / L (building a week) | **Day agenda + swipeable week strip** with dots for open slots and call-outs. Within a day, group by role; tapping an open slot opens the **Assign sheet** (reuse the `shift_assign` payloads and the Everyone / Can work / Free filters). Tapping a shift opens an action sheet: edit, add person, split, merge, remove. Publish & notify is a sticky footer. Replace the dual range-slider split with time pickers. Hide the Gantt views on phones, or make them read-only. |
| Availability | 1 | M–H | Push the day as a page; the route already exists. |
| **Approve Hours** | 1 | **H** | Action sheet per entry; sticky "Approve all (N hrs)". |
| Approved hours, org chart, regulars, roles & departments | 1 | L | Org chart becomes an indented list. |
| Staff profile (7 tabs) | 2 | M | Section list; tap-to-call. |
| Add-staff wizard | 1 | M | Already shaped like a mobile flow. |
| **Pay People** (incl. tips) | 2 | M (tips on the night: H) | Keep the accordion; add a sticky grand total and CTA; Hours and Tips become full-height sheets with steppers. |
| Taxes (W-9 / 1099) | 2 | L | Each row opens a detail sheet; PDFs open in the document viewer. |
| Settings / agreement templates | 1–2 | L | Fine as is. |

### Money: overall 1.4
| Page | Score | Pri | On a phone |
|---|---|---|---|
| Money hub | 1 | H | To-do counts as the main cards. |
| Financials lists | 1 | M | Fine as is. |
| **Show settlement** (financials + worksheet) | 2 | **H** | Make the worksheet a real full page; its `edit` template is missing today, see §6. Stacked sections, sticky **running net**, inline expense rows, and a **snap receipt** camera action (the input rejects `image/*` today). |
| **Show payouts** | 2 | **H** | Sticky bar whose button follows the payout's state: Calculate → Add to run → Pay. Acts and Customize become full-screen sheets with stepper rows and a sticky total. Tooltip text appears inline (e.g. why a payout failed). |
| Payouts lists / runs list | 1 | H | Fine as is. |
| **Payout run detail** | 2 | **H** | Review-and-pay confirm sheet; Stripe funding setup in an in-app browser that returns to the app. |
| Incoming / payment detail | 1 | M–H | **Collect sheet**: QR, share link, **Tap to Pay** (the bridge already exists for the Door). |
| Advances (production page has 3 tables) | 1–2 | L–M | Card rows grouped by status. |
| Calculations / wizard / expenses / settings | 1–2 | L | Wizard shell; tier rows. |
| Books (superadmin only) | 2 | L | Ledger rows grouped by month. |

### Contracts: overall 2
| Page | Score | Pri | On a phone |
|---|---|---|---|
| Contracts hub | 1 | H | 2×2 stats. "In motion" cards with an action strip, modelled on `/my/contracts`. Fix the calendar's `mobile_show_past`. |
| All / completed | 1 | M | Fine as is; add search. |
| **Contract detail** | 2 | **H** | Reorder for phones: status → money → **Next action** card → payments → bookings → docs → terms. Kebab becomes an action sheet; about 6 modals per payment row become sheets. Add a QR hand-off for "sign or pay here". |
| Wizard: about, documents, review | 1 | L | Wizard shell. |
| Wizard: schedule / financials / ticketing & services | 2 | L | Line-item editor with a sticky total. Recommend drafting new contracts on desktop. |
| Wizard: prepare / sign / send | 1–2 | M–H | Full-page document reader; the licence-schedule table overflows today. |
| Amend: dates / space | 1 | M | Keep / Move / Remove per night. |
| Amend: deal | 2 | L | Reuses the wizard steps. |
| Contractors / settings / templates | 1–2 | L–M | Template editor gets an "Insert field" chip picker. |

### Reports: overall 1–2
| Page | Score | Pri | On a phone |
|---|---|---|---|
| Catalogue | 1 | M | Fine as is. |
| 10 reports (one shared `reports/show`) | 1 (≤4 columns) / 2 (wide) | M | **Responsive data table**: each row becomes a card with 2–3 key figures and an expander; total as a card. CSV and print go to the share sheet. |

### Settings & admin: overall 2 (all L unless noted)
| Page | Score | Pri | On a phone |
|---|---|---|---|
| Production edit (9 tabs) | 2 | L | Add the phone `<select>` (`tabs_controller` supports it) or use `settings_layout` sections. Team rows become cards with a ⋯ menu instead of hover actions. |
| Org settings / team / locations | 2 | L | Same team-row fix. |
| Production wizard, producer setup, org select, team invite accept | 1 | L–M | Fine as is. Invite-accept pages are opened from email on phones. |
| Billing | 1 | L | App Store policy decision (see Phase 0). |

---

## 5. Proposed mobile components, ranked by leverage

These are web components (ERB partial + Stimulus), so they also improve mobile web. Items marked **native** go through a Bridge Component.

| # | Component | Replaces | Screens it unlocks |
|---|---|---|---|
| 1 | **Sheet** (`shared/sheet`): bottom sheet on phone, centered card from `sm:`, pink header kept, full-height variant, plus a route-backed variant so deep flows can be pushed as native modal screens | About 205 hand-rolled `fixed inset-0` modals. Starting point: `my/work_availability/_sheet_frame` and the casting board's assign sheet | Nearly every 2 |
| 2 | **Action sheet / ⋯ overflow** (**native** `UIAlertController` via the planned `Menu` bridge, falling back to a web sheet) | Kebab dropdowns, hover-only reveals, wrapped rows of pink `top_menu` buttons in native, sidebar "Actions" cards | Show detail, contract detail, show payouts, run detail, talent pools, team, timesheets, 1099s, tier menu |
| 3 | **Sticky action bar + nav-bar Save** (`data-bridge-title` is wired in `bridge/form_controller.js` but **no page uses it yet**). The main button follows the record's state | Sidebar action tiles that end up below long lists on phones; inline Save/Submit | Show payouts, settlement, casting board (Notify), scheduling (Publish), approve hours, pay people, vacancies, every edit page |
| 4 | **People Picker sheet**: search, single or multi-select, availability filter and badges, eligibility lock with "assign anyway", "already in show" and conflict badges, add guest; loaded per context in a lazy turbo-frame so it's always fresh | Drag from the talent pool, add-person modal, vacancy checkbox lists, talent-pool add, role eligibility, compose recipients, team add, door access, staff assign | Casting board, vacancies, talent pools, compose, staffing scheduling, casting tables, team, sign-up add-person, audition scheduling, casting select, questionnaire invites (**4+ separate implementations exist today**) |
| 5 | **Pivot views** for grids: *Show → people* list (Available / No response / Unavailable), *Person → shows* list, *Session checklist*, *Show pager with load chips*, *Day agenda + week strip* | Every people × shows/days/sessions matrix | All of the 3s |
| 6 | **Filter sheet + search-first header** | `shared/filters/_filter_bar` (`bare` variants have no phone toggle) | Shows, messages, orders, directory, money lists, casting index |
| 7 | **Number row + sticky running total / stepper** (generalize `show_financials/_ticket_line` and the Door's 44px steppers) | Worksheet grids, act counts, custom amounts, tips, comps, sold elsewhere, advances, tier prices | Settlement, show payouts, pay people, ticket show page, payout wizard |
| 8 | **Contact row** (headshot `rounded-lg`, name, subline, call / text / email / message) | Directory tiles, hover-only Contact/Message buttons, member chips | Directory, person, group, course registrants, staff roster |
| 9 | **Responsive data table**: per-column priority; rows become cards below `sm`; total row becomes a card. Builds on `slim_list` | Real `<table>`s in `overflow-x-auto` (22 files) | Reports, advances, books, ticket tables, pass holders |
| 10 | **Section list** (tabs become a drill-in list; each section is a page or sheet; generalizes `settings_layout`'s select) | Tab strips on edit pages | Show edit, production edit, staff profile, course edit |
| 11 | **Wizard shell**: "Step 3 of 6", sticky Back/Next or nav-bar Next, every step inside the modal | 14 `*_wizard` layouts | Shows, productions, courses, contracts, casting tables, sign-up forms, auditions, payouts, staff, deals |
| 12 | **Reorder mode**: explicit Edit, ↑/↓ or handle-only long-press (copy `running_order_controller`'s grip-only touch) | `role_order`, `show_roles_modal` drag, question order, tier order | Casting settings, running order, question builders, ticket tiers |
| 13 | **Stat tiles** (2×2 on phone; one partial, merging about 6 copies) | Per-page stat-box grids | Ticketing, money, contracts, reports, courses, door |
| 14 | **Share / QR / Collect sheet** (**native** share sheet, full-screen QR, Tap to Pay) | `shared/_copy_url`, QR modals, "Copy pay link" | Registration links, ticket links, contract sign/pay, incoming payments |
| 15 | **Native export** (**native** QuickLook / share sheet via `open_in: document`) | CSV links, `window.print`, inline PDFs | Reports, guest/door list, rosters, tax forms, signed contracts |
| 16 | **Keyboard-aware rich-text editor** with a merge-field chip picker | Trix in `100vh` cards; hand-typed `{{field}}` | Documents, contract/agreement/staffing templates, compose |
| 17 | **Slot Picker sheet** (tap a target instead of dragging; date pills + times, modelled on the talent `_open_slot_picker`) | `assign_drag` and other drag-to-slot interactions | Sign-up assign, move registration, audition sessions |
| 18 | **Review card + vote bar** (swipe, "next unvoted", haptics; merges the two duplicated phone vote bars) | Two copies of the vote bar | Audition requests, session run-sheet, casting select |
| 19 | **Question Builder** (cards, full-screen editor, reorder mode) | Three near-duplicate builders | Sign-up forms, audition forms, questionnaires, wizard form_starter |

**Mobile web vs. app:** every component ships to both, gated by screen width. Only #2 (action sheet), #14 (share), #15 (export) and the mode switch have a native version in the app, each a Bridge Component that upgrades the same action, with the web version as the fallback (the app already has this pattern: Menu, DoorScanner, TapToPay, DocumentPresenter). Everything else is plain Rails/Tailwind and is identical in mobile Safari and the app.

---

## 6. Things found along the way (not fixed; this was read-only)

**Live in V1 today**
- `app/views/my/courses/show.html.erb:205`: the instructor's **Message** button is `opacity-0 group-hover:opacity-100`. On iPhone it is invisible but still tappable, because of Tailwind v4's hover gating. Worth fixing before V1 ships.

**Web bugs**
- `Manage::ShowFinancialsController#edit` renders an `edit` template that **doesn't exist** (`app/views/manage/show_financials/` has only `show`, `_worksheet_modal`, `_ticket_line`). `show_payouts_controller.rb:73` redirects there ("enter financial data first"), and a failed `update` renders `:edit`. Both would raise a missing-template error.
- `role_order_controller.js:75-83` binds touch to the whole role card and calls `preventDefault()` on every touchmove. This blocks page scrolling over the list, and a tap posts a reorder.
- Gaps in the casting board's phone assign sheet:
  - It disables anyone already in the show, which breaks act mode (one performer, several acts).
  - Its list goes stale after assigning.
  - Restricted roles fail silently: the server returns 422 and the response is ignored.
  - "Can't make it" on a finalized cast is hover-only (`_finalized_cast.html.erb:128`).
- Ticketing "Sold elsewhere" row (`_outside_sales_row:5`): the fixed grid leaves about 0px for the ticket-type name at 390px.
- Course show: "Mark completed" and "Reopen" exist only in the `hidden sm:flex` desktop block.
- Contracts hub calendar doesn't pass `mobile_show_past`, so the phone list hides earlier overdue payments.
- Pink-standard violations:
  - `contracts/show.html.erb`: the upload and reopen modals have white headers.
  - `contract_settings/sections/_services.html.erb:53`: Remove uses `variant: "danger"`.
  - `shared/_attendance_modal`: white header.

**Docs and cleanup**
- **CLAUDE.md's route section is out of date.** `org_shows`, `org_signups`, `org_auditions` and `org_roles` controllers don't exist; e.g. `/manage/shows` → `shows#org_index`.
- Apparently dead code:
  - `shared/messages/_thread_display`
  - `manage/course_offerings/_form`
  - `money_financials/_third_party_financials`, `_show_row`, `_toggle_filters`
  - `casting_availability/org_partials/*`
  - `email_logs#show` (nothing links to it)
  - Old drag-to-schedule auditions: `auditions/_right_list`, `_sessions_list`, `audition_sessions/_dropzone`
  - `questionnaires/request_invitations` (no route)
- Duplicated talent-pool member grid (initial render vs AJAX refresh), so any fix has to go in both.
- `staffing/scheduling.html.erb:536`: the "Swipe to see all roles" hint shows on phones, where the roles are stacked and there is nothing to swipe.

---

## 7. Suggested V1.1 sequencing

1. **Phase 0: shell.**
   - Mode switch, org switcher, Manage layout, path config.
   - Sheet, action sheet, sticky bar / nav-bar Save.
   - Hover sweep.

   Nothing ships without this, and it immediately makes every 1 usable.
2. **Phase 1: show night and on the go.** All H, mostly 1s and 2s.
   - Home and production dashboard; Messages; show list and show detail; attendance.
   - Casting board; vacancies; "Can't make it".
   - Ticketing dashboard, show page → Door; orders.
   - Contacts.
   - Notifications (§9): the model, ticketing's groups first, the Notifications list.
   - Staffing hub (Find cover), Approve Hours.
   - Money hub, settlement, show payouts, payout run.
   - Contract detail; course show, attendance, add student.
   - Sign-up roster (day-of line-up); audition review and voting; session run-sheet.

   New components: People Picker, Contact row, Number row + running total, Collect sheet, Review card.
3. **Phase 2: running the week.**
   - Compose; show edit; Scheduling as a day agenda; availability pivots; Pay People.
   - Sign-up assign; audition requests list; schedule auditions; casting select; Reports; talent pools.

   New components: Pivot views, Filter sheet, Responsive table, Section list, Slot Picker.
4. **Phase 3: setup and desk work.** Comes in at "functional", redesigned later.
   - Wizards (wizard shell); settings; templates; production edit.
   - Casting Tables; form builders (Question Builder); sign-up and audition settings; Books; taxes.
   - Notifications matrix; questionnaire responses table.

   These work today at 390px or with small fixes, so they can ship *in* the app without a redesign and improve later.

**Options for the low-priority 3s** (Casting Tables, notifications matrix, questionnaire responses table, the Scheduling Gantt):
- (a) Ship them read-only on the phone with an "Edit on a bigger screen" note.
- (b) Ship them working but unoptimized.
- (c) Build the pivot redesign.

Phase 3 assumes (b). That keeps "everything comes in" true without blocking V1.1 on the hardest screens.


---

## 8. Revised after Fable's review

Fable checked the load-bearing claims against the code; all of them held. Changes to this plan:

**New Phase 0 blockers**
- **Path rules and the menu are server-loaded and unversioned.** `SceneDelegate.swift:50` and `AppConfig.swift:24` read one `path-configuration.json` from the server, so any change reaches V1 apps already installed.
  - Fix: a versioned path-config address per app build, plus a user-agent marker the server checks before sending production menu items.
  - Add `/manage/*` to universal links only once V1.1 is the minimum build.
- **`Manage::ManageController` inherits from `ActionController::Base`** (`manage_controller.rb:4`). It lacks `resolve_layout` and `ActivityTracking`.
  - Move it under `ApplicationController`.
  - Also fix the three places that force `/my`:
    - `concerns/authentication.rb:66-70`
    - `AppShell.swift:128` (add a `/start` route that opens the last mode)
    - `AppReturnsController::ALLOWED_PATH`
  - The `^/select/` and `^/superadmin` Safari rules need decisions too.

**Phase 0 split**
- **0a plumbing.** Invisible. Can start now (see §0):
  1. Reparent the controller.
  2. Add an organization-context concern for both controller roots.
  3. Menu data v2 with `mode`, `kind` and one `badge_total`.
  4. Add `/start`.
  - The versioned path config and user-agent marker ride in V1.1 itself.
- **0b components:** sheet, action sheet, sticky bar and nav-bar Save, and the hover sweep. The hover sweep shouldn't wait for anything.

**Phase 1 split**
- **1a, the smallest show-night slice:** enter/exit, production home, casting board, vacancies, Contacts, and the ticketing show page handing off to the Door.
- **1b:** money (settlement, payouts, run), contracts, courses, sign-up roster, audition voting.

**Deferred**
- **Unified inbox.** It's a data-model merge: subscription-based vs. visibility-based, and unread lives on subscriptions. Ship V1.1 with the existing production inbox and one server-computed badge, then unify behind a switch.
- **Push routing.** Pushes need routing by notification type; today every push opens `/my/messages/:id`.
- **`last_dashboard`.** Store it on the user. Update it only on real page loads, not Turbo frames or prefetches, and throttle the writes.

**Cut or defer from the in-app redesign:** the documents editor, contract wizard financials, Books, the notifications matrix, questionnaire responses, and in-app billing (link out instead). Keep course attendance.

**App mode cue:** a "Production mode · organization" strip under the native nav bar, in the app's frame, so it never scrolls away. The switch notice fades after a few seconds.

**V1 triage**
- Must ship before launch:
  - the active_storage document rule
  - turning off swipe-to-dismiss on form sheets
  - email-link sign-in
  - the four hover-only buttons
  - the ranking scroll fix
  - keeping marketing and Manage out of the app
- Hide sign-up questions now, and build answer storage next.
- Can wait a sprint: profile credits, the resume picker, reset password, the W-9 field.
- Missed in the first pass: impersonating in the app has no Stop control, and Manage lacks activity tracking.
- Security look: the `except: %i[index]` access guards (`manage_controller.rb:21-28`).

**Decisions for the owner:** decided 2026-10-20, see §0a.

Correction: "Talent Dashboard" and "Production Dashboard" have 11 and 8 mentions in 8 files.

---

## 9. Notifications, separate from Messages (added 2026-10-16)

*Tim, 2026-10-16: "maybe messages should just become messages between people." Moved here from the ticketing notifications plan, which it absorbs.*

**Why.** Today 31 places in 24 services send automated notices as Messages (`system_generated: true`): payout sent or returned, contract countersigned and signature reminders, casting, vacancies, sign-ups, auditions, course registrations and cancellations, staff onboarding, W-9 requests, availability nudges, mics, and more. They all land in the same inbox as real conversations, so the inbox reads like a log. Separately, Ticketing's notices are email-only and set in a grid of boxes (12 kinds × every manager, one manager filling it in for everyone).

**The split**
- **Messages:** people talking to people. Cast and team threads, DMs, replies. A new one still pushes.
- **Notifications:** automated events. Each is a short line with a link to the thing it's about ("Dan signed the contract", "Your pay is on its way", "A ticket sold"). It reaches you by **push**, **email**, and a **Notifications list** in the app and on the web, depending on what you chose for its group.
- **Replies:** some automated notices get answered today (a performer replying to a casting notice; replies to system messages go to the production team). Those notifications carry a **Reply** that opens a real message thread with the team. The notice itself is never the thread.

**The model**
- One `Notification` record per person: kind, group, title, body, link path, what it's about, read time.
- Per-person preferences: a few **groups**, each with **Push** and **Email** switches, plus sensible defaults. The list always shows everything.
- Each person picks their own push and email per group (Tim, 2026-10-16). Nobody manages a grid for the team. **Ticketing email is the one exception, locked 2026-10-20:** the organization gives each manager or address an email plan on Ticketing settings → Notifications (built 2026-10-20, `TicketingNotifications::PLANS`), because that page also covers addresses that aren't users. Each person still sets **push** per ticketing group on their own settings; the Email column there reads "By plan" and links to the ticketing page.
- All copy stays in ContentTemplates (subject, body, `push_body`).
- Delivery: `PushNotificationService.notify` (push without a Message) and the existing mailers.

**Ticketing goes first** (the ticketing notifications plan of 2026-10-16, built on this model):

| Group | Notices (`TicketingNotifications::KINDS`) | Default push | Default email |
|---|---|---|---|
| Each sale | sale | on | off |
| Daily summaries | daily_summary, show_day, after_show | off | on |
| Selling out | almost_sold_out, sold_out, sales_opened | on | on |
| Money | refund_issued, withdrawal, cancellation_done | off | on |
| Problems | refund_problem, dispute | on | on |

- A push only goes to someone with the app and notifications on. Disputes still also email CocoScout's superadmins.
- **Box office inboxes:** org-level addresses with the groups they get, email only.
- Ticketing settings → Notifications stays as built on 2026-10-20: one row per manager or address with its email plan, Edit opens the plan modal, Add an email address for inboxes. (Superseded here: the "Your notifications" 5 × Push / Email page and its migration.)
- Push starts at the defaults in the table above; the groups are the four `TicketingNotifications::KINDS` groups (Sales as they happen, Reports, Milestones, Money), so the table's five collapse to those.
- Tim's channel decision for ticketing: push and email (and the Notifications list), never the Messages inbox.

**Then the rest, one area at a time:** payouts and payments, contracts, casting and vacancies, sign-ups and auditions, courses, staffing (onboarding, W-9s, availability), mics. Each area gets its groups, moves its senders off `system_generated` Messages, and keeps every email it sends today. When the last one moves, Messages is people only.

**In the apps:** a bell in the native nav bar with an unread count (2026-10-20: universal, not a menu tile), opening the Notifications list, which opens each notification's link. Pushes from notifications open their link. iOS and Android both: the server pieces are shared, and the list is a web page like everything else.

**Design work first:** the settings screen (phone and desktop), the Notifications list, and a few pushes as they'd arrive. Then build ticketing, then move the other areas.

**Mockups (2026-10-20):** row 6 of the navigation canvas (https://claude.ai/artifact/CNaAubdaxfkbdn3ST59LwG): My Notifications on desktop, Account settings → Notifications on desktop, both on mobile web, the app's Notifications screen, and pushes as they arrive. The menus and the desktop sidebar gained a Notifications item with its own count, in both modes (the list is the person's, not the mode's).

**Reconciled with what was built on 2026-10-20** (Ticketing settings → Notifications, "Concept A": the organization gives each manager or address an email *plan*: Everything, The usual, Just the money, Pick my own, Nothing; `TicketingNotifications::PLANS`). That stays as the organization's email policy, since it also covers addresses that aren't users. The person's own settings add **push** per ticketing group; their Email column reads "By plan" and links to the ticketing page. Tim locked that split on 2026-10-20. Still open: whether the app's one badge total adds notifications to messages and tasks, and the label ("My Notifications" on the web, "Notifications" on tiles).

## 10. Built on branch v1.1 (2026-10-20)

Worktree `.claude/worktrees/v1.1`, pushed to origin/v1.1; never deployed until both app reviews pass. `main` stays the production line.

- **Plumbing:** app builds say their navigation generation in the user agent ("CocoScout/1.1 (12; nav 2)", `NativeAppVersion`); generation 2 reads `public/hotwire-native/nav-2/path-configuration.json`, which keeps `/manage` in the app. V1's file never changes. Manage inherits ApplicationController; `OrganizationContext` holds the organization lookup; `/start` opens the last mode.
- **Notifications (§9):** `Notification` + `NotificationGroups` + `Notifier`; Ticketing's notices reach managers' lists and phones; Pay and Contracts moved off automated Messages (2026-10-20; `ContentTemplateService.deliver(notification:)`), Contracts' email always goes; `/notifications` list with the mode-switch prompt; Account settings → Notifications rebuilt. Other areas moved the same day (below); the last three on 2026-10-21: a vacancy invitation is a Casting notification (it was sent as a message from a team member), a questionnaire invitation is a voiced Invitations notification (a Message too when the manager changed the words, like the other voiced ones), and the Tap to Pay launch is a Ticketing milestone notification. Mics keep their messages (their code isn't touched).
- **Desktop panel:** `shared/navigation/panel_frame` for every panel; switcher retired; Work the door black.
- **Mobile web:** `shared/navigation/mobile_grid_nav` rebuilt (icons in the top bar, organization sheet, bars at the bottom).
- **Apps:** `NativeAppHelper#native_nav` for generation 2 only (the bridge adds it only when present); iOS `NavMenuViewController` and nav-bar icons; Android `NavMenuSheet` and `ToolbarIcons`; Coco has no badge; sticky production strip in the app layout.

Casting and vacancies, sign-ups and auditions, courses, and shifts moved too (2026-10-20): `MessageService.create_message` turns an automated message whose template is in `NotificationGroups::TEMPLATES` into a Notification (full words on its own page when it has no link); message-only ones still reach email through the unread digest. Notices a manager can write or edit (casting notices, audition results, the roster, onboarding, W-9 and availability requests, payout setup reminders, group invitations, contract invoices; `NotificationGroups::VOICED`) follow option 3 (Tim, 2026-10-20): always a Notification; also a Message from the manager when they changed the words or added a note (`ManagerWords`, the sender passes `custom_words:`). One push (the Message's when there is one), one email, and reading the Message reads the Notification. My Messages has a Notifications row at the top, for V1 phones without a bell. - **Phase 0b (2026-10-20):** the hover sweep (42 controls; `pointer-fine:` hides until hover only with a mouse; `spec/lib/hover_only_controls_spec.rb` keeps new ones out) and three shared pieces: `shared/sheet` (bottom sheet on a phone, pink-header modal from sm up), `shared/action_menu` (⋯: dropdown, or the same items in a sheet on a phone) and `shared/sticky_actions` (a form's buttons pinned to the bottom on a phone, clear of the Coco button in the app). Native upgrades (action sheet, nav-bar Save) come later, behind the same markup.

- **Phase 1a (2026-10-20):** production Home and each production's dashboard open on a Needs attention stack on a phone; the casting board has a pinned count + Notify bar, Replace on filled slots, and the assign sheet's §6 gaps closed (act mode, staleness, restricted roles, refusals; Move to… still desktop drag); a vacancy sorts invitees by availability with tags and a pinned Send; Contacts opens on contact rows (Call / Text / Email) and a person's page has a Call / Text / Email / Message row; the ticketing show page has a pinned Door button and a ⋯ menu of its actions.

- **Phase 1b (2026-10-20):** a show's settlement opens as its own page on a phone (the worksheet with a phone-camera receipt upload) and its payouts page has a pinned bar; confirm modals are bottom sheets on a phone; the contract page stacks for a phone with pink upload and reopen headers; a course's page has Mark completed / Reopen on a phone and attendance takes one session at a time as a checklist with a running count; the sign-up roster's Move and Remove are 44px targets; the audition vote bar says Yes / No / Not sure in words, swipes between requests, and names the next one I haven't voted on with the count left.

- **Phase 2, first half (2026-10-20):** compose is a full-screen sheet on a phone with both steps' buttons pinned; a show's settings open on a list of sections to drill into (the tabs controller's drill mode) with Save pinned; Scheduling is a week strip (dots for shows and open slots, swipe along the week) with one day's shifts under it, the Gantt charts kept for desktop, the assign modal a sheet, Publish or Notify updates pinned; the availability grids pivot into lists (a production's shows with counts or its people; the organization's per-show list under each production) with the modals and the row-action popup as sheets; Pay People pins the running total and the button, opens Hours, the pull, Tips and the review steps as sheets, and has a half-hour stepper on the hours line (`number_stepper`).

- **Phase 2, second half (2026-10-20):** sign-up assign places people by tap (Pick a slot or Move opens a sheet of slots with room; the queue first; Auto-assign All pinned; Add to Queue a sheet; drag stays for a mouse); the audition requests list has compact rows with vote chips, Everyone / Not voted by me / Most yes first as links, and a Select mode with the archive bar pinned; schedule auditions opens Add and Review & notify as full-screen sheets with Review & notify pinned and a real Remove target; casting select's sheet wears the pink header with 44px decisions (reject in dark gray) and Done Selecting pinned; a report's rows are cards on a phone with the total as a card (the table stays for sm up and print); the talent pool's tiles open their actions in a sheet (`tile_sheet`) and its add and remove modals are sheets. Not done from those rows: casting select still has its own row markup rather than the review card, and the talent pool's Add is still its own search, not the People Picker.

- **Phase 3 (2026-10-20):** a wizard says Step N of M with a bar and what's next on a phone (the circles stay for sm up; Back and Next stay in each step's form, the nav-bar Next is a native upgrade for later); a settings page's sections open from a sheet (`shared/settings_layout`); every template editor has Insert field chips (`merge_field`); production edit drills into sections (`shared/section_panel_header`, the tabs controller's drill mode) and its team rows stack; a casting table pages one show at a time with each person a row that opens the picker as a sheet (`show_pager`), the grid for md up; the question editor is a full-screen sheet and touch reorder lives on the grip handle; Books heads its entries by month and draws the ticket money by show as cards; the Taxes rows fit a phone. Then (2026-10-21) the three it left: `shared/_offset_input` draws every days/hours/minutes triplet (sign-up settings' edit and cancel cutoffs, the sign-up wizard's opens and closes) with 44px boxes on a phone and the same names; the contract money step's payment lines have a 44px remove and its Add a payment is a bottom sheet with the pink header and pink buttons; and a questionnaire's responses table is one card per response on a phone (each question's answer under it, `_answer_cell` shared with the table, which stays from md up).

- **Android pass (2026-10-20):** read against the iOS app and the server, piece by piece. Already there from Phase 0a: the user-agent marker (`AppConfig.userAgentPrefix`, set before any web view), the generation-2 page rules (the app bundles `public/hotwire-native` as assets, so `nav-2/` ships inside it), `/start` as the start location, the V1.1 menu sheet (`NavMenuSheet`: person card with close, Profile / Settings / Sign out, the organization row in production mode, tiles, Work the door black, the switch CocoScout pink), the toolbar's Messages and Notifications with counts (`ToolbarIcons`), no badge on Coco once a V1.1 menu arrives, and pushes opening their `path` (the plan's "push routing" note was stale: both apps already open a notification's page). Fixed: the toolbar icons are added once per toolbar (a configuration change rebuilt the view and would have doubled them). Page rules (both apps, `nav-2` only, kept by `spec/lib/path_configuration_spec.rb`, which also pins V1's file): a wizard's steps after `/new` stay in the modal (`/new/`); the three tabbed edit pages (`staffing/staff/:id/edit`, `ticketing/shows/:id/edit/…`, `casting/tables/:id/edit/…`) are pages, not modals; the reports, 1099 and roster CSVs open in the phone's viewer. The Kotlin compiles (Android Studio's JDK). Live in the Pixel 8 emulator against localhost on this branch (`adb reverse tcp:3000 tcp:3000`, since the debug build's base URL is localhost): sign-in, Home with the Messages count and the bell, the My menu (person card, Home / Shows & Events tiles, the pink Enter bar), Enter production mode (the organization strip, the production inbox count), the production menu (organization row, four tiles a row, Pro locked, the pink Exit bar), the casting board with its pinned bar clear of Coco, show edit as a modal opening on the sections list with Sections / Basic Information and Save pinned, and the bell opening Notifications. All as designed.

- **iOS pass (2026-10-20):** live in the iPhone 16 Pro simulator against localhost on this branch: welcome, sign-in, Home with the Messages count and the bell, the My menu, Enter production mode (the switch notice over the organization strip, the production inbox count), the production menu (organization row, four tiles a row, Pro locked, the pink Exit bar). The same web pages as Android inside; the frame matches the design. Also built: Reply on a notification that came with the manager's words opens their thread; Move to another act on the casting board by tap on a phone (`drop-role#openMoveSheet`); the comps modal is a sheet on a phone (Sold elsewhere already was).

- **One Messages inbox (2026-10-21; Tim: "I would like to do the merge"):** the mail icon opens the same list in either mode (`MessagesInbox`, `shared/messages/_inbox`, `Message.inbox_for`): every thread the person is subscribed to plus the production-side threads of every organization they can open, archived ones aside. Each row is under a hat: nothing for a thread they're in as a performer; a pill naming the organization for a thread of a production they run (pink when it's the organization open in production mode, gray for another). The For chips keep Everything, As a performer, or one organization; Show has All / Unread / Sent by me / Archived in both modes. A row opens through `my/messages/:id/open`: a production-side thread opens in production mode for its organization (switching organization when it's another one), and from My or from another organization's production mode it asks first in the pink-header prompt (`shared/mode_switch_prompt`, the notifications' Don't ask again), a performer thread opens on My. One count on the icon in both modes (`unread_message_count`); the organization-scoped count and inbox-scoped Mark all read are gone, and a thread about a production is now stored as that production's organization's. The data model didn't need merging: both inboxes already read the same subscriptions, so the plan's §8 deferral is closed.

- **Review card and the one vote bar (2026-10-21):** `shared/_review_card` draws a person being reviewed the same way everywhere: headshot with the decision badge, name, a line under it (the RSVP on a run-sheet, the decision's words on casting select), and the votes as chips on a phone and thirds from sm up. On it: the audition requests list, a session's run-sheet (its phone rows now get chips), and casting select's auditionees (its wide list and its phone sheet, which lost its own row markup). `shared/_vote_bar` is the one bar on a request's page and on a session audition's page (words, swipe, the next one I haven't voted on when the page knows it; the session page's emoji are gone).

- **§0a and §6 checked end to end (2026-10-21):** in place already: superadmin, billing and the marketing pages open in Safari from the app; the labels are Home and Shows & Events; impersonating in the app shows the "You're impersonating · Stop" bar; a notification whose page lives in production mode asks first; Coco has no badge and the iOS tile counts are pink; the `except: %i[index]` guards hide no hole (`set_current_organization` and `set_current_production` already drop an organization or production whose access went away, and `require_current_organization` runs on every action). Fixed now: the mode is remembered on the account too (`users.last_mode`, written on real page loads only and only when it changes; `/start`, the universal pages' panel and the account menu fall back to it on a new phone), "Start producing" is website-only (the web menus hide it under the app's user agent; the native menu never had it), roles reorder by touch from the grip only (the page scrolls over the cards, a tap reorders nothing), and the Contracts hub calendar's phone list keeps the month's earlier days (overdue payments). `spec/requests/v1_1_decisions_spec.rb` and `start_spec.rb` keep these.

- **Live in both apps against localhost on this branch (2026-10-21):** the demo organization got four upcoming Open Mic Nights (two with a Host cast) so the pages can be reached by tapping. Android (Pixel 8 emulator) and iOS (iPhone 16 Pro simulator), both: the app opens in production mode (the last mode), Home with the organization band, the one mail count and the Oct 27 show in the phone calendar; the show page; the casting board with its pinned count + Notify bar; Replace opens the People Picker as a sheet (search by name, "Already in this show", the guest row); Messages is the one inbox with the organization pills and the Show / For chips; the bell opens Notifications. Found and fixed on the way: the app's own `DELETE /my/push-token` call ran the My-mode tracker and flipped the mode cookie, so the next production page showed the switch notice and the next launch would have opened My (both trackers now count real page loads only); an empty talent pool said "Nobody to add yet" instead of saying it's the pool. Release work from here is in `docs/v1_1_release_checklist.md`.

- **Crossing modes, the whole rule (Tim's review, 2026-10-21):** something for a production you run opens in that production's organization in production mode, and asks first when that means leaving where you are (My, or another organization's production mode: "Open in production mode?" / "Switch to Moonlight Players?", with Don't ask again); something that's yours as a performer opens where you already are and switches nothing. So: an inbox row, a message push and a notification's Reply all go through `my/messages/:id/open`, which reads a performer thread in production mode's own frame when that's where you are (the thread page offers no "as the production team" reply there, and the server refuses one for a production you don't run); the Notifications list asks from production mode too when a notice is another organization's, and never for the organization already open or for a My page. The one place the frame still changes without a word: a notification whose page is a My page (your pay, your shows), opened from production mode, goes to that page, since My pages live in My.

- **The /open links audited, and the switch said out loud (2026-10-21):** every notification kind was traced to its page: the message-born ones take the first link in their words (vacancy, show, review, registrations, course offering, scheduling, talent pool and the Tap to Pay settings page for managers; audition, onboarding, W-9, 1099, availability, shifts, contracts and payments pages for performers; sign, pay and claim pages by token for anyone), the job-sent ones carry their path (payout batches and contracts for managers, payments setup and My Contracts for payees and signers), ticketing's carry the show's or the ticketing page, and the ones with no link open their own words. Every page routes; every notice whose page is in production mode carries its organization, so `open` can switch there. One sender was still a Message (the sign-up registration notice to the team) and is a Notification now. `open` also stops short for an organization the person can no longer open (their own words instead of a page that turns them away). And after any switch an opener makes, organization or mode, the next page says "Switched to Moonlight Players. You're in production mode." for five seconds with Exit (the same soft pink notice as a link into /manage), so Don't ask again never leaves a switch unannounced.

- **One page-top model, one Messages page, the switch said every time (Tim's review, 2026-10-21):** `shared/module_header` is the header of every landing page in both modes (the My pages moved off `top_menu`; inner pages keep it): the title in Coustard, a description for desktop only, and the actions as cards from sm up or, on a phone, icon tiles in one row that scrolls sideways with no scrollbar and an arrow at whichever end has more (`shared/section_tiles`, `scroll_row`; Tim chose "B · icon tiles" on the headers canvas); one or two actions are buttons in the title row at every width, so Messages has Send a message and Mark all read, not sections; the "Sections" fold is gone; in the app the nav bar keeps the title. Home puts its title first, then what needs attention (the welcome guide follows), then the calendar, in both modes. "Home" everywhere; "My Shows & Events" on My (web, mobile grid, both apps' menus), "Shows & Events" in production mode. Messages is one page at `/messages` (`MessagesController`, drawn in the mode's frame like Notifications; `/my/messages` and `/manage/messages` redirect there): production mode adds Send a message and the intro guide, My the Contact-the-team card, a V1 app the Notifications row; its filters are one line (the search box, then All / Unread / Sent / Archived · Everything / As a performer / each organization · the production dropdown when there's more than one · sort and density as icons), scrolling sideways on a phone. The soft pink notice now follows every switch: entering straight in ("You're in production mode for …"), entering or changing organization through the picker or an opener ("Switched to …"; the picker no longer counts as being in production mode), and leaving ("You left production mode for …"), each once, on the next page.

- **The organization menu, rethought (Tim, 2026-10-21):** it opens from the band that says you're in production mode, so it reads, in order: where you are (the organization, your role, its plan), Exit production mode as the CocoScout-pink bar (moved here from the account menu, which keeps Enter on My), "Switch to" with the other organizations one tap each, "This organization" (settings, plan and billing, Productions or the one production's settings, Add a production), then New organization, quiet. The phone's organization sheet is the same list under a pink "Organization" header. The Productions item in the nav lost its count. Messages' filters are the shared filter bar like every other list (Show, For, the production dropdown, and two round pink icon buttons for newest-oldest and row density), not an inbox-only chip row; the rule that six landing pages drew over their filter bar is gone; and the show wizard says "Schedule an event" everywhere the page that opens it does.

- **People Picker (2026-10-20):** the shared sheet (`shared/_people_picker`, `people_picker` and `people_picker_trigger`, `Manage::PeoplePickerController#search`): one search box, the organization's people with their email, people on CocoScout outside it by name, profile key or exact email with no email shown (PersonSearch), groups when asked, who's already added or in the pool, "In the talent pool" and availability badges for a show, and an invitation for an email nobody has (with a name box when the page needs one). A pick is an event the page handles the way it always did. On it now: sign-up add (a slot or the queue, both pages), the talent pool's add (people, groups, outsiders, invitations), the production team's add (accounts, outsiders, invitations; the old team search endpoint is gone), and a questionnaire's invitations (several at a time). Then (same day) the casting board's phone assign and the vacancy's invitees: the picker lists the talent pool before a search (available for the date first, with a linked event's dates counted), says who's already in the show (a badge on an act-based night, not pickable otherwise), marks who a restricted role hasn't approved (the board still asks before assigning anyway), takes a guest by name, and marks who's invited or can't make it; a vacancy's picks are chips on the form with an Add-all for the approved and available. Then staffing's shift assign: the picker's staff scope lists everyone qualified for the shift's role, free for all of it first, with what they said about the hours, who's on it, who's in a show that night and who's on an overlapping shift (each pick carries the clashes, so the conflict modal still asks first), and the Everyone / Can work / Available the whole shift chips are the picker's filter row. Then audition scheduling's Add auditionees (2026-10-21): the picker's auditionees scope lists the cycle's sign-ups for the session, those marked available first by yes votes, each with what they said and their votes, who's in this session (not pickable) and who's in another; Available / Everyone and Hide already-scheduled / Show scheduled too are two chip groups on the picker's filter row (the sheet now takes several groups), and the page no longer carries the whole cycle's availability in a data attribute. Then the last four (2026-10-21): Ticketing settings → Door access and a show's or production's Visibility page find anyone with an account (and take an email to invite, with a name) through it, marking who has the door or sees the sales; a casting table's Talent Pool tab lists the organization's people and groups before a search (list=org) and marks who's in the table; compose's Individuals step opens it (people picked are chips, with Added marked), and the three old search endpoints (door, visibility, messages' search_people) are gone. Casting select never had a people search (its rows are the review card's work, below).

Nothing left to build for V1.1 (2026-10-21); what remains is release work, listed in `docs/v1_1_release_checklist.md`. After V1.1: the native upgrades (action sheet, nav-bar Save, share sheet), by Tim's call.
- **Empty lists (2026-10-21).** `shared/_empty_state` is the one way to show an empty list in both modes: a dashed box, a gray icon (check, inbox, calendar, people, ticket, document, bell, search, clipboard, money, star, clock, chat), a short title, a line that says what would fill it, and sometimes the button that does (`actions:`); `compact: true` inside a card. It replaced the hand-drawn boxes on My Tasks, My Shows & Events, auditions and their directory, courses and their directory, payments, shifts, ticket sales, the inbox and notifications, and on Shows & Events, Casting, Contracts, Contractors, Courses, Directory, Productions, Sign-ups, sign-up forms, Staff, Casting tables, Incoming money, Financials and Reports; then the rest of the lists: staffing roles, regulars, taxes, timesheets, the schedule week, the org chart, talent pools, ticket listings, attendance, the books, the agreement roster, contract and staff agreement templates, the casting-table wizard and contract financials. An action with no path is a modal trigger (`type: :button` + `data`).
- **Organization menu by plan (2026-10-21, design canvas "Organization menu by tier").** Productions sits in the left nav on every Pro organization, even with one; never on the Producer plan. The organization menu carries the production itself while there is one (its row, with upcoming shows and talent-pool size, opens its settings): on Pro with a plain Add a production under it, on the Producer plan with a Pro card ("Running a second production?", See Pro → Plan and billing) instead of a locked row. With several productions on Pro the menu says nothing about them. "This organization" appears only when its links do.
- **Inbox and notification filters (2026-10-21).** For (Everything / As a performer / each organization you run) and the notifications' About are dropdowns on the shared filter bar, one column, like Production. The inbox keeps one round pink button: newest or oldest first, its arrow pointing the way the list runs. The row-density button is gone (it changed nothing anyone could see).

## 11. Mailing lists and My Followers (built 2026-10-23)

Tim's decisions, 2026-10-23 (design canvas "Mailing lists and My Followers"):
a Pro module for the organization's managers; the word is "followers"; each
organization keeps its own copy of every person; a producer a list is shared
with sees it in My Followers (see, add, export, never send); the checkout box
is ticked by default; sending only from Pro, on its own Mailgun domain.

- **Data.** `followers` (one per person per organization: status, consent,
  unsubscribe token), `follower_sources` (every way they arrived or bought:
  checkout, by hand, pasted, Contacts, added by a producer), `mailing_lists`
  (one main list per organization, named after it, plus groups), with
  `mailing_list_productions` (where a list collects at checkout),
  `mailing_list_memberships` and `mailing_list_shares`; `segments` (a jsonb
  rule, SegmentQuery); `follower_emails` (ActionText body, lists and segments,
  show blocks) and `follower_email_deliveries`; platform-wide
  `email_suppressions` (a hard bounce or complaint stops every organization).
- **Production mode.** "Mailing lists" after Ticketing in the Pro nav
  (`:mailing_lists` in PAID_FEATURES and MANAGER_ONLY_FEATURES). Home on
  `shared/module_header`; every sub-page on `shared/top_menu`. A list's
  sidebar: Collects from, Who can see this list, and the standard
  `shared/action_list` (Change who can see it, Change where it collects,
  Export, Rename, Archive). Add people checks a paste first (new, already on
  it, unsubscribed, bounced) and asks for permission. Contacts → a person →
  "Add to a mailing list". Settings: Email look, Checkout, Allowance.
- **Sending.** One copy per follower through FollowerMailer (the
  organization's logo or two letters and color, show blocks with Buy tickets,
  a footer with why, the postal address and Unsubscribe), on
  FOLLOWERS_MAIL_DOMAIN with List-Unsubscribe and one-click, skipping
  EmailLogInterceptor. FollowerEmailSendJob sends what's queued, one
  organization at a time; anyone who left after the send was confirmed is
  skipped. Production refuses to send until the domain is set (release
  checklist §2b). Per-recipient sends rather than Mailgun's batch call, so
  development, tests and production take the same path.
- **What each email sold.** Its links carry `utm_campaign=fe-<id>`; the public
  ticket page keeps it a week (`cs_campaign`) and checkout writes it into the
  order's `utm` (FollowerEmailSales).
- **Checkout.** FollowCheckout: a box for the main list, plus one per list
  collecting from that production ("Send me news about Dan Feltey's shows");
  never at the door. FollowTicketBuyerJob after settlement records what they
  bought and adds them to what they ticked; nobody unsubscribed is put back; a
  buyer who ticked nothing is on no list, and segments only pick people on a
  list, so they're never emailed.
- **My Followers.** In the website's My nav (not the app menu, Tim's rule),
  between My Payments and My Documents; the My nav is now in Tim's order.
  One row per email across organizations, showing only how someone came to a
  list shared with them. Add a follower picks the list; Export emails a CSV of
  everyone still following.
- **Allowance.** 500 emails to followers a month per Pro organization for
  now, a hard stop (Tim, 2026-10-23); more, and paying for more, later.
- **Sharing** uses the standard search-or-invite (the People Picker with
  outside and invite, as Who sees sales): someone new gets a contact, a
  login and the account-setup invitation, and the list is waiting in My
  Followers when they claim it.
- **Not yet.** CSV import, scheduling, a public signup form, door capture,
  buying more emails, opens and clicks.

## 12. Scheduling, redesigned (built 2026-10-24)

Tim (2026-10-24): "we're scrolling far far far too much." Two layouts went on a canvas (https://claude.ai/artifact/TqWHs92iTDLSaCiy1a4HWh); he approved Design A on desktop, the two-month week calendar, and Design B on a phone. It replaces the day-block page (and the phone week strip from §10).

- **Desktop: the week, rotated.** Days across the top, roles down the left (`_week_grid`). A day with nothing on it narrows to a sliver. Under each date, one slim line per show (`_show_line`: time, production, "needs N"; hover for cast and Role Call, click for the show's detail modal). Each shift is one line (`_shift_chip`): its hours, then who's on it; pink when full, red when someone can't make it, dashed while nobody's on it, indigo "also" on a role it also covers. Each day header has "N of M staffed" and a timeline icon that opens that day by role or by person (the old Gantt). Every active role has a row; a cell's "+" adds a shift in that role that day.
- **The shift menu** (`_shift_menu`, `shift_menu_controller`): a chip or a timeline bar opens it, a popover from sm up and a bottom sheet on a phone. It holds everything the old card did: Add a person (Find someone else when someone can't make it), Edit time and covers, Split, Merge, Remove shift, and each person with their reason and Remove.
- **Picking a week:** previous, the week itself (a two-month calendar, `_week_picker` + `_mini_month`, where a click on a week row goes there, each week dotted green published, amber draft or red open slots), next, This week.
- **One status bar** (`_status_bar`) instead of three banners: Draft with Publish & notify, N updates to send with Notify updates and the person chips, or Published with Resend; "N can't make it" opens this week's list (reason and Find someone) with the other weeks' listed by their day; "N services to staff" opens the still-to-staff list with Add the shifts; the week's slots staffed on the right.
- **Phone: one day at a time** (`_phone_day`, `?day=`), never "week". The day's name opens a calendar of any date (Pick a day); the strip keeps the chosen day in the middle, three days either side, across weeks; swipe for the next or previous day (`day_swipe_controller`). The day's roles on a timeline (bars open the shift menu), "+ Add a shift", and the day's shows at the bottom, one line each. Publish stays pinned to the bottom.
- Unchanged: the Add shift, Edit, Split, Merge, People Picker, conflict, show detail and finalize modals, and every route.

## 13. Home, redesigned (built 2026-10-27)

Tim (2026-10-26): "the home screen has become outdated. We don't have anything about ticketing, we don't have anything about staffing there, we have all sorts of stuff about sign-ups… The calendar's too big." Two layouts went on a canvas (https://claude.ai/artifact/4L1wcDByGrrJiXZtGbrd5n); the first draft had rows by module, which Tim turned down ("It needs to be show by show"); he chose Design B, "and it's not even close".

- **The week, show by show** (`manage/manage/_home_week`, `_show_row`): the days across the top, a slim row per show stacked by time under its day, three state chips on each (tickets · staffing · cast; `HomeHelper`): green nothing to do, amber something open, red someone's missing, pink happening now (the door is open). A day with nothing on it narrows to a sliver. Seven days from the week's Monday, or three days from a chosen day (`?days=3`, remembered in the session); the week control is Scheduling's (`shared/_week_picker`, now shared, with `shared/_mini_month`), picking a week or, in the 3-day view, a day.
- **A row opens the show's modal** (`_show_modal`, a `shared/sheet`): its hours and venue; Tickets (sold of capacity, money, comps; tonight's door with Work the door; "not yet, it's a draft"); Staffing (each shift's role, hours and people, "can't make it" in red, "+ Staff" for an open slot, the Draft mark, Scheduling for that day); Cast (vacancies with Review, then the performers as a row of headshot squares with the name on hover: `shared/_faces`, the casting board's way; "N of M cast · all notified"). Open the show at the foot.
- **One Actions box** instead of the old banners and accordions (`_actions`, built by `Manage::ManageController#home_status_items`): one line per thing waiting, its topic on the left (Casting, Sign-ups, Staffing, Ticketing, Money, Contracts), a chevron, the whole line the link, the same at every width; `/manage?all_actions=1` (a superadmin, or development) shows an example of every kind for pruning. (It began as a row of pills on 10/27; Tim, 10/28: "one line at a time… a box that says actions… keep it simple".) The lines: open vacancies (one → Review it; several → a sheet with Review on each), audition sign-ups to review, who's registered for the next event, staffing (draft · can't make it · open slots), Ticketing's alerts (`TicketingDashboard#alerts`), shows whose cast hasn't been notified, shows that need financials, to pay, hours to approve, contracts out for signature. Only what has something in it.
- **Phone** (`_home_day`): Actions, the welcome guide, then one day: the day's name opens Pick a day, the strip keeps the day in the middle (`shared/_day_strip`, now shared with Scheduling), swipe for the next or previous day, each show a row with its chips in words, opening the same modal.
- **Gone:** the month grid (and `calendar_day_controller`), the Audition Sign-ups and Event Registrations accordions, the Open Vacancies panel. Kept: the module header, the welcome guide until dismissed, the empty state for an organization with no productions.
- **Data:** `HomeWeek` (app/services) works a range out in a handful of queries: the shows (what the person can see, canceled ones struck through), their listings and `Ticketing::ListingStats`, the range's shifts matched to shows (tied to the show, or overlapping it), roles and assignments, cast notifications, active vacancies. The week loaders Scheduling and Home share live in `Manage::WeekLoaders`. Tickets and staffing show only for Pro managers (the same gate as the money pills); cast for everyone. A query-slope spec keeps the page's cost flat as shows are added.
- **The dashboard cache** (`DashboardService`, 5 minutes) now keys on each production's sign-up registrations as "count-latest" too: Tim removed a registration and Home still said "1 registered", because a removed row leaves no newer timestamp behind.
