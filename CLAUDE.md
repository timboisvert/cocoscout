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

## Routes

### Money Routes
The money section uses nested routes. Note the route naming convention:
- `manage_production_money_payout_schemes_path` - index
- `manage_production_money_payout_scheme_path(@production, scheme)` - show
- `manage_production_edit_money_payout_scheme_path(@production, scheme)` - edit (edit comes BEFORE money)
- `manage_production_new_money_payout_scheme_path(@production)` - new
