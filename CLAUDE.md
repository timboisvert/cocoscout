# CocoScout Development Guidelines

## UI Components

### Headshots
We always show headshots with the `rounded-lg` class. People and Groups have a `safe_headshot_variant` method that returns an image variant for display.

**In ERB views:**
```erb
<%# Get the headshot variant (returns nil if no headshot) %>
<% headshot_variant = person.safe_headshot_variant(:thumb) %>

<%# Display with fallback to initials %>
<% if headshot_variant %>
  <%= image_tag headshot_variant, alt: person.name, class: "w-10 h-10 rounded-lg object-cover" %>
<% else %>
  <div class="w-10 h-10 rounded-lg bg-gray-200 flex items-center justify-center text-gray-600 font-bold text-sm">
    <%= person.initials %>
  </div>
<% end %>
```

**To get headshot URL for JavaScript/data attributes:**
```erb
<% headshot_url = headshot_variant ? url_for(headshot_variant) : nil %>
<div data-person-headshot-url="<%= headshot_url %>">
```

**In JavaScript (when building HTML dynamically):**
```javascript
const headshotHtml = headshotUrl
  ? `<img src="${headshotUrl}" alt="${name}" class="w-10 h-10 object-cover rounded-lg">`
  : `<span class="text-sm font-bold">${initials}</span>`;
```

### Buttons
All buttons MUST use the `shared/button` partial. Do not create custom button styles or use plain `<a>` or `<button>` elements styled as buttons.

```erb
<%= render "shared/button", text: "Button Text", variant: "primary", size: "medium" %>
```

For links that look like buttons:
```erb
<%= link_to some_path do %>
  <%= render "shared/button", text: "Link Text", variant: "secondary", size: "small" %>
<% end %>
```

For form submit buttons:
```erb
<%= render "shared/button", text: "Submit", variant: "primary", size: "medium", type: :submit %>
```

### Checkboxes
All checkboxes must be styled with pink accent color:

```erb
<%= form.check_box :field_name, class: "h-4 w-4 text-pink-600 border-gray-300 rounded focus:ring-pink-500 accent-pink-600" %>
```

Key classes:
- `text-pink-600` - Pink checkmark color
- `accent-pink-600` - Pink accent for native browser styling
- `focus:ring-pink-500` - Pink focus ring
- `border-gray-300` - Standard border color
- `rounded` - Rounded corners

### Top Menu Breadcrumbs
Breadcrumbs must be passed as arrays of `[name, path]` pairs, not hashes:

```erb
<%= render partial: "shared/top_menu", locals: {
  breadcrumbs: [
    ["Parent Page", parent_path],
    ["Child Page", child_path]
  ],
  text: "Current Page",
  links: []
} %>
```

### Module Header (New Header)
The "new header" for major module landing pages. Uses a large title with `coustard-regular` font, supports multi-line HTML descriptions, and displays action buttons in a 2x2 grid (4 buttons) or 2+1 layout (3 buttons).

```erb
<%= render "shared/module_header",
  title: "Module Title",
  description: "<p class='mb-2'>First paragraph of description.</p><p>Second paragraph.</p>",
  actions: [
    { icon: "calendar", text: "First Action", path: first_path },
    { icon: "clipboard-list", text: "Second Action", path: second_path },
    { icon: "cog", text: "Settings", path: settings_path },
    { icon: "user-group", text: "Fourth Action", path: fourth_path }
  ]
%>
```

**Supported Icons:**
- `calendar` - Calendar icon
- `clipboard-list` - Clipboard list icon
- `user-group` - User group icon
- `cog` - Settings/gear icon
- `users` - Users icon
- `chart-bar` - Chart bar icon
- `dollar-sign` - Dollar sign icon

**Styling Notes:**
- Title uses `text-4xl coustard-regular`
- Description supports raw HTML (use `raw()` helper)
- Buttons have `bg-gray-50 border border-gray-300` with pink icon circles
- Grid is 2x2 for 4 actions, 2+1 (two top, one centered below) for 3 actions

### Show Row
The show_row partial displays a single show/event in a list. It's highly configurable for different contexts (performer view, cast view, manager view, availability tracking, etc.).

```erb
<%= render "shared/show_row",
  show: @show,
  link_path: show_path(@show),  # Optional - makes row clickable
  right_panel: :availability,   # Panel type
  entity: @person,              # For availability/cast display
  entity_key: "person_#{@person.id}",
  availability: @availability
%>
```

**Required Params:**
- `show` - Show object

**Optional Params:**
| Param | Default | Description |
|-------|---------|-------------|
| `link_path` | nil | Makes row clickable, links to this path |
| `show_canceled` | false | Show canceled badge and strikethrough date |
| `show_recurring` | false | Show recurring event indicator |
| `show_linked` | false | Show linked event indicator with tooltip |
| `show_production` | false | Show production name in details line |
| `show_location` | true | Show location/online indicator |
| `role_assignments` | [] | Array of `{role_name:, entity_type:, entity_id:, entity_name:}` |
| `entity` | nil | Person/Group for right panel display |
| `availability` | nil | Availability object for buttons |
| `entity_key` | nil | Entity key for Stimulus data attribute |
| `show_cant_make_it` | false | Show "Can't make it" link |
| `cant_make_it_person` | nil | Person for vacancy token |
| `my_vacancies` | [] | Array of user's vacancies for this show |
| `has_groups` | false | Whether user has groups (affects headshot display) |
| `right_panel` | nil | Panel type: `:cast_assignment`, `:availability`, `:cast_summary`, `:countdown`, or nil |
| `entity_assignments` | [] | Array of `{entity:, role_assignments:}` for stacked cast panels |
| `cast_summary` | nil | Hash with `{assignments_count:, roles_count:, vacancies:}` |
| `closes_at` | nil | DateTime for countdown panel |

**Right Panel Types:**
- `:availability` - Shows availability status buttons (yes/no/maybe)
- `:cast_assignment` - Shows entity headshot and assigned roles
- `:cast_summary` - Shows count of assignments and vacancies
- `:countdown` - Shows countdown timer to closes_at

## Routes

### Money Routes
The money section uses nested routes. Note the route naming convention:
- `manage_production_money_payout_schemes_path` - index
- `manage_production_money_payout_scheme_path(@production, scheme)` - show
- `manage_production_edit_money_payout_scheme_path(@production, scheme)` - edit (edit comes BEFORE money)
- `manage_production_new_money_payout_scheme_path(@production)` - new

## Superadmin Metrics

### "Active" Definitions
- **Active People**: A person is considered "active" if they have a user account with `last_seen_at` within the past 30 days. This means the user has logged in and interacted with the application recently.
- **Active Organizations**: An organization is considered "active" if it has a show with `date_and_time` within 30 days ago to 30 days from now. This means the organization has recent or upcoming events.
