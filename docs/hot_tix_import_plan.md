# Plan: Hot Tix Spreadsheet Import Provider

## Summary

Add a new "Hot Tix" ticketing provider that imports sales data from Excel spreadsheets (no API). The user uploads a `.xls` file, the system parses it, auto-matches rows to existing Shows by date/time + production name, lets the user confirm/fix matches, and imports the ticket sales data into the existing ticketing models.

## Design Decisions

- **Auto-match** events to Shows by date + production name; user confirms matches before import
- **Unmatched rows**: user decides per row (skip or manually assign to a Show)
- **Duplicates**: detect by date + venue + production combo and skip already-imported rows
- Hot Tix is a **no-API provider** (like Manual) — data comes entirely from spreadsheet uploads
- Reuse existing ticketing models (`ShowTicketing`, `ShowTicketTier`, `TicketOffer`, `TicketSale`) — no new tables needed beyond optional import history tracking
- Accept `.xls` files (the format Hot Tix provides); `roo` gem handles both `.xls` and `.xlsx`

## Spreadsheet Structure

The Hot Tix spreadsheet is a "Merchant Account Payment" report structured as follows:

- **Row 1**: Header — `[Hot Tix] Merchant Account Payment`
- **Row 3**: Column group headers — "Outlet" and "Internet" sections, plus "Hot Tix Marketing Fees"
- **Row 4**: Column headers

**Grouped by venue** (e.g., "Stars & Garters Theater"), then per-event rows underneath:

| Column | Field |
|--------|-------|
| A | Date & time (e.g., "April 3, 2026 7:00 PM") — or venue name header, or "Event Total" / "Venue Total" / "Total" |
| B | Production name (e.g., "Comedy Pageant") |
| C | (unused) |
| D | Outlet: Tickets sold |
| E | Outlet: Ticket Type |
| F | Outlet: Face Value |
| G | Internet: Tickets sold |
| H | Internet: Ticket Type |
| I | Internet: Face Value |
| J | Total Tickets Sold |
| K | Total Hot Tix Sales ($) |
| L | Hot Tix Ticket Price |
| M | Marketing Fee (%) |
| N | Total Marketing Fee ($) |
| O | Total Due ($) |

**Summary rows to skip**: "Event Total", "Venue Total", "Total" — these are aggregates, not individual sales.

**Venue header rows**: Identified by having a non-date value in column A with no production name in column B. The current venue applies to all event rows below it until the next venue header.

## Steps

### Phase 1: Dependencies & Provider Registration

1. **Add `roo` gem** to `Gemfile`
   ```ruby
   gem "roo", "~> 2.10"
   ```
   Then `bundle install`. The `roo` gem handles both `.xls` and `.xlsx` natively.

2. **Add `hot_tix` entry** to `config/ticketing_providers.yml`
   ```yaml
   hot_tix:
     display_name: "Hot Tix"
     icon: "HT"
     website: "https://www.hottix.org"

     capabilities:
       api_fetch_events: false
       api_create_event: false
       api_update_event: false
       api_fetch_sales: false
       api_sync_inventory: false
       webhook_sales: false
       webhook_inventory: false
       supports_recurring: false
       supports_draft: false
       requires_approval: false
       supports_import: true

     credentials: {}
     required_permissions: []
     webhooks: null

     health_checks:
       - type: always_valid
         message: "Hot Tix uses spreadsheet import — no connection needed"
   ```

3. **Add `"hot_tix"` to `PROVIDER_TYPES`** in `app/models/ticketing_provider.rb`
   ```ruby
   PROVIDER_TYPES = %w[eventbrite ticket_tailor manual hot_tix].freeze
   ```
   And add the adapter case to the `#adapter` method:
   ```ruby
   when "hot_tix"
     TicketingAdapters::HotTixAdapter.new(self)
   ```

### Phase 2: Adapter & Import Service

4. **Create `app/services/ticketing_adapters/hot_tix_adapter.rb`**
   - Extend `ManualAdapter` (inherits no-API behavior)
   - Override `fetch_sales` to reference spreadsheet import
   - Add `supports_import?` → `true`
   - `test_connection` → always succeeds

5. **Create `app/services/hot_tix_import_service.rb`** — the core logic

   **Public API:**
   ```ruby
   service = HotTixImportService.new(organization, file)
   preview = service.preview    # parse + match, no writes
   result  = service.import!(matched_rows)  # execute import
   ```

   **Parsing logic (`parse!`):**
   - Open file with `Roo::Spreadsheet.open(file)`
   - Walk rows top to bottom:
     - Identify **venue header rows**: column A has text, column B is blank, and column A doesn't match a date pattern or summary keyword
     - Identify **event rows**: column A matches a date/time pattern (e.g., `Month D, YYYY H:MM PM`)
     - **Skip** rows where column A contains "Event Total", "Venue Total", or "Total"
   - For each event row, extract:
     - `date_time` (parsed from column A)
     - `production_name` (column B)
     - `venue_name` (from current venue header context)
     - `outlet_tickets` (column D, integer)
     - `outlet_ticket_type` (column E, string)
     - `outlet_face_value` (column F, dollars)
     - `internet_tickets` (column G, integer)
     - `internet_ticket_type` (column H, string)
     - `internet_face_value` (column I, dollars)
     - `total_tickets_sold` (column J)
     - `total_hot_tix_sales` (column K, dollars)
     - `hot_tix_ticket_price` (column L, dollars)
     - `marketing_fee_pct` (column M, percentage)
     - `total_marketing_fee` (column N, dollars)
     - `total_due` (column O, dollars)

   **Matching logic (`match_to_shows!`):**
   - For each parsed row, find the best matching Show in the organization:
     - Match by `date_and_time` (same calendar day)
     - AND production name similarity (`production.name` or `show.secondary_name` contains/fuzzy-matches the spreadsheet's production name)
   - Return confidence: `:high` (date + name match), `:low` (date only), `:none` (no match)

   **Import logic (`import!`):**
   - For each confirmed match (row → Show):
     1. Find or create `ShowTicketing` for the Show
     2. Find or create `ShowTicketTier` entries for each ticket type found (e.g., "General", "Price Level B @")
     3. Find or create `TicketListing` linked to the Hot Tix `TicketingProvider`
     4. Create `TicketOffer` per tier per listing
     5. Create `TicketSale` records — one per sales channel (outlet, internet) if tickets > 0
     6. Update `ShowTicketTier` sold/available counts via `record_sale!`
   - **Dedup**: Before creating a `TicketSale`, check for existing sale with same `show_ticket_tier` + `purchased_at` date + `ticket_offer` belonging to this provider. Skip if found.
   - Store Hot Tix-specific data in `TicketSale#sale_data` (jsonb):
     ```json
     {
       "source": "hot_tix",
       "import_date": "2026-03-09",
       "venue": "Stars & Garters Theater",
       "channel": "internet",
       "marketing_fee_pct": 5,
       "marketing_fee_cents": 150,
       "total_due_cents": 2850,
       "hot_tix_ticket_price_cents": 1500
     }
     ```

### Phase 3: Controller & Routes

6. **Add import routes** to `config/routes.rb` under the ticketing providers resource:
   ```ruby
   resources :ticketing_providers do
     member do
       # ... existing routes ...
       get :import
       post :import, action: :process_import
       post :confirm_import
     end
   end
   ```

7. **Add controller actions** to `app/controllers/manage/ticketing_providers_controller.rb`:

   - `import` — render upload form (guard: only for `hot_tix` providers)
   - `process_import` — receive file via `params[:file]`, parse with `HotTixImportService`, store preview data in session, render preview page
   - `confirm_import` — read confirmed matches from session + form params, execute `service.import!`, redirect to provider show page with flash summary

   Add `import` and `process_import` and `confirm_import` to the `before_action :set_provider` list.

### Phase 4: Views

8. **Create `app/views/manage/ticketing_providers/import.html.erb`**
   - Top menu breadcrumbs (array format per project conventions):
     ```erb
     breadcrumbs: [
       ["Ticketing", manage_ticketing_path],
       [@provider.name, manage_ticketing_provider_path(@provider)]
     ],
     text: "Import Spreadsheet"
     ```
   - File upload form with drag-and-drop zone
   - Accept `.xls` and `.xlsx` files
   - Submit button using `shared/button` partial
   - Brief instructions: "Upload your Hot Tix Merchant Account Payment spreadsheet"

9. **Create `app/views/manage/ticketing_providers/preview_import.html.erb`**
   - Table showing parsed rows:
     | Date | Production | Venue | Outlet Tix | Internet Tix | Total Sold | Face Value | Fees | Total Due | Match Status |
   - Match status per row:
     - Green check + Show name = high confidence match
     - Yellow warning = low confidence (user should verify)
     - Red X = unmatched → show a dropdown to manually select a Show, or a "Skip" checkbox
   - Duplicate warnings: if a row matches already-imported data, show "Already imported" badge and auto-skip
   - Summary bar: "X of Y rows matched, Z skipped, $N total revenue"
   - Confirm Import button (`shared/button`, variant: "primary") + Cancel link
   - Hidden fields carrying the parsed data + match selections

10. **Add "Import Spreadsheet" button** to `app/views/manage/ticketing_providers/show.html.erb`
    - Only visible when `@provider.provider_type == "hot_tix"`
    - Add to the entity header actions or as a prominent button in the provider detail section
    - Links to `import_manage_ticketing_provider_path(@provider)`

### Phase 5: Stimulus Controller

11. **Create `app/javascript/controllers/spreadsheet_import_controller.js`**
    - Connect to the upload form
    - File input with drag-and-drop support
    - Validate file type (`.xls`, `.xlsx` only)
    - Validate file size (max 5MB)
    - Show file name after selection
    - Loading/spinner state during upload+parse
    - On the preview page: handle "skip" checkboxes and manual show-picker dropdowns

### Phase 6: Optional — Import History Tracking

12. **Consider adding a `hot_tix_imports` table** (can defer)
    ```ruby
    create_table :hot_tix_imports do |t|
      t.references :ticketing_provider, null: false
      t.string :file_name
      t.integer :rows_parsed
      t.integer :rows_imported
      t.integer :rows_skipped
      t.integer :total_tickets
      t.integer :total_revenue_cents
      t.jsonb :import_summary, default: {}
      t.timestamps
    end
    ```
    This would allow showing past imports on the provider page and potentially supporting "undo import" (delete all `TicketSale` records with matching `sale_data.import_id`).

    **For the initial implementation, this is optional.** The `sale_data` jsonb on `TicketSale` is sufficient for dedup and auditing.

## Files to Modify

| File | Change |
|------|--------|
| `Gemfile` | Add `gem "roo", "~> 2.10"` |
| `config/ticketing_providers.yml` | Add `hot_tix` provider definition |
| `app/models/ticketing_provider.rb` | Add `"hot_tix"` to `PROVIDER_TYPES`, add adapter case |
| `config/routes.rb` | Add `import`, `process_import`, `confirm_import` member routes |
| `app/controllers/manage/ticketing_providers_controller.rb` | Add 3 new actions + before_action |
| `app/views/manage/ticketing_providers/show.html.erb` | Add "Import Spreadsheet" button for hot_tix |

## Files to Create

| File | Purpose |
|------|---------|
| `app/services/ticketing_adapters/hot_tix_adapter.rb` | Adapter class (extends ManualAdapter) |
| `app/services/hot_tix_import_service.rb` | Spreadsheet parsing, show matching, import logic |
| `app/views/manage/ticketing_providers/import.html.erb` | Upload form view |
| `app/views/manage/ticketing_providers/preview_import.html.erb` | Preview + confirm view |
| `app/javascript/controllers/spreadsheet_import_controller.js` | File upload UX |

## Testing

1. **Unit test `HotTixImportService`** with a fixture `.xls` file:
   - Verify parsing extracts correct event rows
   - Verify summary rows ("Event Total", "Venue Total", "Total") are skipped
   - Verify venue context is correctly tracked across rows
   - Verify both outlet and internet channels are extracted
   - Verify dollar amounts are correctly converted to cents

2. **Unit test show matching**:
   - High confidence: exact date + production name match
   - Low confidence: date match only
   - No match: different date
   - Fuzzy name matching (e.g., "Comedy Pageant" matches production named "Comedy Pageant")

3. **Unit test duplicate detection**:
   - Import same file twice → no duplicate `TicketSale` records created
   - Import overlapping files → only new rows imported

4. **Integration test**:
   - Full flow: upload → preview → confirm → verify all records created
   - Verify `ShowTicketing`, `ShowTicketTier`, `TicketListing`, `TicketOffer`, `TicketSale` all created correctly
   - Verify `sale_data` contains Hot Tix metadata

5. **Edge cases**:
   - Empty file
   - File with only summary rows (no event data)
   - Unrecognized date formats
   - Missing columns
   - Event row with 0 outlet tickets and >0 internet tickets (and vice versa)
   - Multiple venues in one file
   - Very large file (performance)

## Scope Boundaries

**Included:**
- Hot Tix provider type registration
- `.xls` spreadsheet import (`.xlsx` also supported via `roo`)
- Auto-matching rows to Shows by date + production name
- Preview/confirm flow before importing
- Sales data storage with marketing fee tracking
- Duplicate detection

**Excluded:**
- Automated/scheduled imports (manual upload only)
- Hot Tix API integration (none exists)
- Export functionality
- Modifying the ticketing dashboard views (existing views will display imported data automatically via existing models)
- Undo/rollback of imports (can add later with import history table)
