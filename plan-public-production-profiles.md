# Plan: Public Production & Show Profile Pages

Add public profile pages for productions at `/:public_key` and their shows at `/:public_key/:show_id`, with visibility controls at production and show levels, following the existing Person/Group public profile patterns.

## Overview

Productions will get unique public keys (like people and groups) allowing them to be viewed at `cocoscout.com/:public_key`. Shows/events of that production will be accessible at `cocoscout.com/:public_key/:show_id`. Visibility is controlled at three levels:
1. **Event type defaults** - shows, classes, workshops default to visible; rehearsals, meetings default to hidden
2. **Production overrides** - can override defaults for each event type
3. **Individual show overrides** - can override for specific shows

---

## Steps

### 1. Create Database Migrations

**File:** `db/migrate/XXXXXX_add_public_profile_to_productions.rb`

Add to `productions` table:
- `public_key` (string, unique index, nullable)
- `old_keys` (text, for JSON array of previous keys for redirects)
- `public_key_changed_at` (datetime)
- `public_profile_enabled` (boolean, default: true)
- `event_visibility_overrides` (text, for JSON hash of event_type → boolean)

**File:** `db/migrate/XXXXXX_add_public_visibility_to_shows.rb`

Add to `shows` table:
- `public_profile_visible` (boolean, nullable - nil means use production/event type default)

**File:** `config/profile_settings.yml`

Extend event_types with `public_visible_default`:
```yaml
event_types:
  show:
    label: "Show"
    casting_enabled_default: true
    public_visible_default: true
  rehearsal:
    label: "Rehearsal"
    casting_enabled_default: false
    public_visible_default: false
  meeting:
    label: "Meeting"
    casting_enabled_default: false
    public_visible_default: false
  class:
    label: "Class"
    casting_enabled_default: true
    public_visible_default: true
  workshop:
    label: "Workshop"
    casting_enabled_default: true
    public_visible_default: true
```

---

### 2. Extend Production Model

**File:** `app/models/production.rb`

Add validations and callbacks matching Person model pattern:

```ruby
# Validations
validates :public_key, uniqueness: true, allow_nil: true
validates :public_key, format: {
  with: /\A[a-z0-9][a-z0-9\-]{2,29}\z/,
  message: "must be 3-30 characters, lowercase letters, numbers, and hyphens only"
}, allow_blank: true
validate :public_key_not_reserved
validate :public_key_change_frequency

# Callbacks
before_validation :generate_unique_public_key, on: :create
before_save :track_public_key_change, if: :public_key_changed?

# Methods
def generate_unique_public_key
  return if public_key.present?
  self.public_key = PublicKeyService.generate_unique_key(name)
end

def track_public_key_change
  return unless public_key_was.present?
  current_old_keys = old_keys.present? ? JSON.parse(old_keys) : []
  current_old_keys << public_key_was unless current_old_keys.include?(public_key_was)
  self.old_keys = current_old_keys.to_json
  self.public_key_changed_at = Time.current
end

def public_key_not_reserved
  return if public_key.blank?
  reserved = YAML.load_file(Rails.root.join("config", "reserved_public_keys.yml"))["reserved_keys"]
  errors.add(:public_key, "is reserved") if reserved.include?(public_key)
end

def public_key_change_frequency
  return if public_key_changed_at.nil?
  cooldown = Rails.application.config_for(:profile_settings)[:url_change_cooldown_days] || 365
  if public_key_changed_at > cooldown.days.ago
    errors.add(:public_key, "can only be changed once every #{cooldown} days")
  end
end

def public_profile_url
  return nil unless public_key.present?
  Rails.application.routes.url_helpers.public_profile_url(public_key, host: Rails.application.config.action_mailer.default_url_options[:host])
end

# Event visibility - returns effective visibility for an event type
def event_type_visible?(event_type)
  overrides = event_visibility_overrides.present? ? JSON.parse(event_visibility_overrides) : {}
  return overrides[event_type] if overrides.key?(event_type)
  EventTypeSettingsHelper.public_visible_default(event_type)
end

def set_event_visibility_override(event_type, visible)
  overrides = event_visibility_overrides.present? ? JSON.parse(event_visibility_overrides) : {}
  overrides[event_type] = visible
  self.event_visibility_overrides = overrides.to_json
end
```

**File:** `app/services/public_key_service.rb`

Update `key_taken?` method to also check Production:

```ruby
def self.key_taken?(key)
  Person.exists?(public_key: key) ||
  Group.exists?(public_key: key) ||
  Production.exists?(public_key: key)
end
```

---

### 3. Extend Show Model

**File:** `app/models/show.rb`

Add visibility method:

```ruby
# Returns whether this show should be publicly visible
# Priority: show override → production override → event type default
def public_profile_visible?
  # If show has explicit override, use it
  return public_profile_visible unless public_profile_visible.nil?

  # Otherwise use production's setting for this event type
  production.event_type_visible?(event_type)
end
```

**File:** `app/helpers/event_type_settings_helper.rb`

Add helper method:

```ruby
def self.public_visible_default(event_type)
  settings = Rails.application.config_for(:profile_settings)
  settings.dig(:event_types, event_type.to_sym, :public_visible_default) || false
end
```

---

### 4. Add "Public Profile" Tab to Production Edit

**File:** `app/views/manage/productions/edit.html.erb`

Add Tab 3 "Public Profile" after "Visual Assets" (before "Danger Zone"):

```erb
<!-- Tab 3: Public Profile -->
<div data-tabs-target="panel" class="hidden">
  <div class="space-y-6">
    <!-- Public Profile URL Section -->
    <div class="border border-gray-200 rounded-lg p-4">
      <h3 class="text-lg font-semibold text-gray-900 mb-4">Public Profile URL</h3>

      <% if @production.public_profile_enabled %>
        <%= render "shared/copy_url", url: @production.public_profile_url, label: "Your public profile" %>
      <% else %>
        <p class="text-gray-500 text-sm">Public profile is disabled</p>
      <% end %>

      <!-- Enable/Disable Toggle -->
      <div class="mt-4 pt-4 border-t border-gray-200">
        <%= form_with model: @production, url: manage_production_path(@production), method: :patch, data: { turbo: false } do |f| %>
          <label class="flex items-center gap-2 cursor-pointer">
            <%= f.check_box :public_profile_enabled, class: "rounded border-gray-300 text-pink-500 focus:ring-pink-500" %>
            <span class="text-sm font-medium text-gray-700">Enable public profile page</span>
          </label>
          <p class="text-xs text-gray-500 mt-1 ml-6">When enabled, anyone can view this production's public page</p>
          <%= f.submit "Save", class: "mt-3 cursor-pointer bg-pink-500 hover:bg-pink-600 text-white px-4 py-2 rounded text-sm" %>
        <% end %>
      </div>
    </div>

    <!-- Custom URL Section -->
    <div class="border border-gray-200 rounded-lg p-4">
      <h3 class="text-lg font-semibold text-gray-900 mb-4">Custom URL</h3>

      <%= form_with model: @production, url: manage_production_path(@production), method: :patch, data: { controller: "public-key-editor" } do |f| %>
        <div class="flex items-center gap-2">
          <span class="text-gray-500">cocoscout.com/</span>
          <%= f.text_field :public_key,
              class: "flex-1 rounded-lg border border-gray-300 px-3 py-2 text-sm focus:ring-pink-500 focus:border-pink-500",
              pattern: "[a-z0-9][a-z0-9\\-]{2,29}",
              data: { public_key_editor_target: "input" } %>
        </div>
        <p class="text-xs text-gray-500 mt-2">3-30 characters. Lowercase letters, numbers, and hyphens only.</p>

        <% if @production.public_key_changed_at.present? %>
          <p class="text-xs text-amber-600 mt-2">
            Last changed <%= time_ago_in_words(@production.public_key_changed_at) %> ago.
            Can be changed again after <%= (@production.public_key_changed_at + 365.days).strftime("%B %d, %Y") %>.
          </p>
        <% end %>

        <%= f.submit "Update URL", class: "mt-3 cursor-pointer bg-pink-500 hover:bg-pink-600 text-white px-4 py-2 rounded text-sm" %>
      <% end %>
    </div>

    <!-- Event Type Visibility Defaults -->
    <div class="border border-gray-200 rounded-lg p-4">
      <h3 class="text-lg font-semibold text-gray-900 mb-2">Event Visibility Defaults</h3>
      <p class="text-sm text-gray-500 mb-4">Control which event types appear on your public profile by default. You can override these for individual events.</p>

      <%= form_with model: @production, url: manage_production_path(@production), method: :patch, data: { turbo: false } do |f| %>
        <div class="space-y-3">
          <% EventTypeSettingsHelper.event_types.each do |event_type| %>
            <% default_visible = EventTypeSettingsHelper.public_visible_default(event_type) %>
            <% current_visible = @production.event_type_visible?(event_type) %>
            <label class="flex items-center gap-2 cursor-pointer">
              <%= check_box_tag "event_visibility[#{event_type}]", "1", current_visible,
                  class: "rounded border-gray-300 text-pink-500 focus:ring-pink-500" %>
              <span class="text-sm font-medium text-gray-700"><%= event_type.titleize.pluralize %></span>
              <% unless current_visible == default_visible %>
                <span class="text-xs text-amber-600">(overridden from default: <%= default_visible ? "visible" : "hidden" %>)</span>
              <% end %>
            </label>
          <% end %>
        </div>
        <%= f.submit "Save Visibility Settings", class: "mt-4 cursor-pointer bg-pink-500 hover:bg-pink-600 text-white px-4 py-2 rounded text-sm" %>
      <% end %>
    </div>
  </div>
</div>
```

**File:** `app/controllers/manage/productions_controller.rb`

Update `update` action to handle visibility overrides:

```ruby
def update
  # Handle event visibility overrides
  if params[:event_visibility].present?
    EventTypeSettingsHelper.event_types.each do |event_type|
      visible = params[:event_visibility][event_type] == "1"
      @production.set_event_visibility_override(event_type, visible)
    end
  end

  if @production.update(production_params)
    redirect_to edit_manage_production_path(@production), notice: "Production updated."
  else
    render :edit, status: :unprocessable_entity
  end
end

private

def production_params
  params.require(:production).permit(:name, :description, :contact_email, :logo,
    :public_key, :public_profile_enabled)
end
```

---

### 5. Add "Public Visibility" Box to Show Edit

**File:** `app/views/manage/shows/edit.html.erb`

Add after the Casting Settings box (~line 228):

```erb
<!-- Public Visibility Settings -->
<div class="border border-gray-200 rounded-lg overflow-hidden mt-4">
  <div class="bg-gray-50 px-4 py-3 border-b border-gray-200">
    <h3 class="text-md font-semibold text-gray-900 coustard-regular">Public Profile Visibility</h3>
  </div>
  <div class="p-4">
    <p class="text-sm text-gray-600 mb-3">
      Control whether this <%= @show.event_type %> appears on the production's public profile page.
    </p>

    <% default_visibility = @production.event_type_visible?(@show.event_type) %>
    <div class="space-y-2">
      <label class="flex items-center gap-2 cursor-pointer">
        <%= f.radio_button :public_profile_visible, "", checked: @show.public_profile_visible.nil?, class: "text-pink-500 focus:ring-pink-500" %>
        <span class="text-sm text-gray-700">
          Use production default
          <span class="text-gray-500">(<%= default_visibility ? "visible" : "hidden" %> for <%= @show.event_type.pluralize %>)</span>
        </span>
      </label>
      <label class="flex items-center gap-2 cursor-pointer">
        <%= f.radio_button :public_profile_visible, "true", checked: @show.public_profile_visible == true, class: "text-pink-500 focus:ring-pink-500" %>
        <span class="text-sm text-gray-700">Show on public profile</span>
      </label>
      <label class="flex items-center gap-2 cursor-pointer">
        <%= f.radio_button :public_profile_visible, "false", checked: @show.public_profile_visible == false, class: "text-pink-500 focus:ring-pink-500" %>
        <span class="text-sm text-gray-700">Hide from public profile</span>
      </label>
    </div>
  </div>
</div>
```

**File:** `app/controllers/manage/shows_controller.rb`

Update permitted params to include `public_profile_visible` and handle the conversion:

```ruby
def show_params
  permitted = params.require(:show).permit(:date_and_time, :secondary_name, :location_id,
    :event_type, :casting_enabled, :is_online, :online_location_info, :public_profile_visible, ...)

  # Convert public_profile_visible to proper boolean/nil
  if permitted[:public_profile_visible].present?
    if permitted[:public_profile_visible] == ""
      permitted[:public_profile_visible] = nil
    else
      permitted[:public_profile_visible] = permitted[:public_profile_visible] == "true"
    end
  end

  permitted
end
```

---

### 6. Add Routes and Extend Controller

**File:** `config/routes.rb`

Add production and show public profile routes (BEFORE the existing `/:public_key` route):

```ruby
# Public profile pages
get "/:public_key/shoutouts", to: "public_profiles#shoutouts", constraints: { public_key: /[a-z0-9][a-z0-9\-]{2,29}/ }
get "/:public_key/:show_id", to: "public_profiles#production_show", constraints: { public_key: /[a-z0-9][a-z0-9\-]{2,29}/, show_id: /\d+/ }
get "/:public_key", to: "public_profiles#show", constraints: { public_key: /[a-z0-9][a-z0-9\-]{2,29}/ }
```

**File:** `app/controllers/public_profiles_controller.rb`

Extend `show` action to handle Production and add `production_show` action:

```ruby
def show
  public_key = params[:public_key]

  # Try Person first
  @person = Person.find_by(public_key: public_key)
  if @person
    return render :not_found, status: :not_found unless @person.public_profile_enabled?
    return render :person
  end

  # Try Group
  @group = Group.find_by(public_key: public_key)
  if @group
    return render :not_found, status: :not_found unless @group.public_profile_enabled
    return render :group
  end

  # Try Production
  @production = Production.find_by(public_key: public_key)
  if @production
    return render :not_found, status: :not_found unless @production.public_profile_enabled?

    # Load visible shows
    @shows = @production.shows
      .where(canceled: false)
      .order(date_and_time: :asc)
      .select { |show| show.public_profile_visible? }

    @upcoming_shows = @shows.select { |s| s.date_and_time >= Time.current }
    @past_shows = @shows.select { |s| s.date_and_time < Time.current }

    return render :production
  end

  # Check old_keys for redirects
  @person = Person.where("old_keys LIKE ?", "%#{public_key}%").find { |p|
    JSON.parse(p.old_keys || "[]").include?(public_key)
  }
  if @person&.public_key
    return redirect_to public_profile_path(@person.public_key), status: :moved_permanently
  end

  @group = Group.where("old_keys LIKE ?", "%#{public_key}%").find { |g|
    JSON.parse(g.old_keys || "[]").include?(public_key)
  }
  if @group&.public_key
    return redirect_to public_profile_path(@group.public_key), status: :moved_permanently
  end

  @production = Production.where("old_keys LIKE ?", "%#{public_key}%").find { |p|
    JSON.parse(p.old_keys || "[]").include?(public_key)
  }
  if @production&.public_key
    return redirect_to public_profile_path(@production.public_key), status: :moved_permanently
  end

  render :not_found, status: :not_found
end

def production_show
  @production = Production.find_by(public_key: params[:public_key])

  unless @production&.public_profile_enabled?
    return render :not_found, status: :not_found
  end

  @show = @production.shows.find_by(id: params[:show_id])

  unless @show && !@show.canceled? && @show.public_profile_visible?
    return render :not_found, status: :not_found
  end

  # Load cast with eager loading
  @assignments = @show.show_person_role_assignments
    .includes(:role, :assignable)
    .order("roles.position ASC, roles.created_at ASC")

  render :production_show
end
```

---

### 7. Create Public Profile Views

**File:** `app/views/public_profiles/production.html.erb`

```erb
<% content_for :title, @production.name %>

<div class="min-h-screen bg-gray-50">
  <!-- Hero Section -->
  <div class="bg-white border-b border-gray-200">
    <div class="max-w-4xl mx-auto px-4 py-8">
      <div class="flex flex-col md:flex-row gap-6 items-start">
        <!-- Production Image -->
        <div class="flex-shrink-0">
          <% poster = @production.primary_poster %>
          <% if poster&.image&.attached? %>
            <%= image_tag poster.image.variant(:medium), class: "w-48 h-auto rounded-lg shadow-lg" %>
          <% elsif @production.logo.attached? %>
            <%= image_tag @production.safe_logo_variant(:small), class: "w-48 h-auto rounded-lg shadow-lg" %>
          <% else %>
            <div class="w-48 h-64 bg-gray-200 rounded-lg flex items-center justify-center">
              <span class="text-4xl font-bold text-gray-400"><%= @production.initials %></span>
            </div>
          <% end %>
        </div>

        <!-- Production Info -->
        <div class="flex-1">
          <h1 class="text-3xl font-bold text-gray-900 coustard-regular"><%= @production.name %></h1>
          <p class="text-lg text-gray-600 mt-1"><%= @production.organization.name %></p>

          <% if @production.description.present? %>
            <div class="mt-4 text-gray-700 prose prose-sm max-w-none">
              <%= simple_format(@production.description) %>
            </div>
          <% end %>

          <% if @production.contact_email.present? %>
            <div class="mt-4">
              <a href="mailto:<%= @production.contact_email %>" class="text-pink-500 hover:text-pink-600">
                <%= @production.contact_email %>
              </a>
            </div>
          <% end %>
        </div>
      </div>
    </div>
  </div>

  <!-- Upcoming Shows -->
  <% if @upcoming_shows.any? %>
    <div class="max-w-4xl mx-auto px-4 py-8">
      <h2 class="text-xl font-semibold text-gray-900 mb-4">Upcoming Shows & Events</h2>
      <div class="space-y-3">
        <% @upcoming_shows.each do |show| %>
          <%= link_to public_profile_path(@production.public_key, show.id), class: "block bg-white rounded-lg border border-gray-200 p-4 hover:border-pink-300 transition-colors" do %>
            <div class="flex justify-between items-start">
              <div>
                <div class="font-semibold text-gray-900">
                  <%= show.secondary_name.presence || show.event_type.titleize %>
                </div>
                <div class="text-sm text-gray-600">
                  <%= show.date_and_time.strftime("%A, %B %d, %Y at %l:%M %p") %>
                </div>
                <% if show.location.present? %>
                  <div class="text-sm text-gray-500 mt-1">
                    <%= show.location.name %>
                  </div>
                <% elsif show.is_online? %>
                  <div class="text-sm text-gray-500 mt-1">Online Event</div>
                <% end %>
              </div>
              <span class="text-xs px-2 py-1 bg-gray-100 rounded text-gray-600"><%= show.event_type.titleize %></span>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
  <% end %>

  <!-- Past Shows -->
  <% if @past_shows.any? %>
    <div class="max-w-4xl mx-auto px-4 py-8">
      <h2 class="text-xl font-semibold text-gray-900 mb-4">Past Shows & Events</h2>
      <div class="space-y-3">
        <% @past_shows.first(10).each do |show| %>
          <%= link_to public_profile_path(@production.public_key, show.id), class: "block bg-white rounded-lg border border-gray-200 p-4 hover:border-pink-300 transition-colors opacity-75" do %>
            <div class="flex justify-between items-start">
              <div>
                <div class="font-medium text-gray-700">
                  <%= show.secondary_name.presence || show.event_type.titleize %>
                </div>
                <div class="text-sm text-gray-500">
                  <%= show.date_and_time.strftime("%B %d, %Y") %>
                </div>
              </div>
              <span class="text-xs px-2 py-1 bg-gray-100 rounded text-gray-500"><%= show.event_type.titleize %></span>
            </div>
          <% end %>
        <% end %>
        <% if @past_shows.count > 10 %>
          <p class="text-sm text-gray-500 text-center">And <%= @past_shows.count - 10 %> more...</p>
        <% end %>
      </div>
    </div>
  <% end %>

  <!-- No Shows Message -->
  <% if @upcoming_shows.empty? && @past_shows.empty? %>
    <div class="max-w-4xl mx-auto px-4 py-8 text-center text-gray-500">
      <p>No public shows or events scheduled yet.</p>
    </div>
  <% end %>
</div>
```

**File:** `app/views/public_profiles/production_show.html.erb`

```erb
<% content_for :title, "#{@show.secondary_name.presence || @show.event_type.titleize} - #{@production.name}" %>

<div class="min-h-screen bg-gray-50">
  <!-- Breadcrumb -->
  <div class="bg-white border-b border-gray-200">
    <div class="max-w-4xl mx-auto px-4 py-3">
      <%= link_to @production.name, public_profile_path(@production.public_key), class: "text-pink-500 hover:text-pink-600 text-sm" %>
      <span class="text-gray-400 mx-2">›</span>
      <span class="text-gray-600 text-sm"><%= @show.secondary_name.presence || @show.event_type.titleize %></span>
    </div>
  </div>

  <!-- Show Details -->
  <div class="bg-white border-b border-gray-200">
    <div class="max-w-4xl mx-auto px-4 py-8">
      <div class="flex flex-col md:flex-row gap-6">
        <!-- Show Poster or Production Image -->
        <div class="flex-shrink-0">
          <% if @show.poster&.attached? %>
            <%= image_tag @show.poster.variant(:medium), class: "w-48 h-auto rounded-lg shadow-lg" %>
          <% elsif @production.primary_poster&.image&.attached? %>
            <%= image_tag @production.primary_poster.image.variant(:medium), class: "w-48 h-auto rounded-lg shadow-lg" %>
          <% elsif @production.logo.attached? %>
            <%= image_tag @production.safe_logo_variant(:small), class: "w-48 h-auto rounded-lg shadow-lg" %>
          <% end %>
        </div>

        <!-- Show Info -->
        <div class="flex-1">
          <span class="text-xs px-2 py-1 bg-pink-100 text-pink-700 rounded"><%= @show.event_type.titleize %></span>
          <h1 class="text-2xl font-bold text-gray-900 mt-2 coustard-regular">
            <%= @show.secondary_name.presence || @show.event_type.titleize %>
          </h1>
          <p class="text-lg text-gray-600"><%= @production.name %></p>

          <!-- Date & Time -->
          <div class="mt-4 flex items-center gap-2 text-gray-700">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
            </svg>
            <span><%= @show.date_and_time.strftime("%A, %B %d, %Y at %l:%M %p") %></span>
          </div>

          <!-- Location -->
          <% if @show.is_online? %>
            <div class="mt-2 flex items-center gap-2 text-gray-700">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9" />
              </svg>
              <span>Online Event</span>
            </div>
          <% elsif @show.location.present? %>
            <div class="mt-2 flex items-center gap-2 text-gray-700">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
              </svg>
              <span><%= @show.location.name %></span>
            </div>
            <% if @show.location.address1.present? %>
              <div class="ml-7 text-sm text-gray-500">
                <%= @show.location.address1 %><%= ", #{@show.location.city}" if @show.location.city.present? %>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
  </div>

  <!-- Cast Section -->
  <% if @show.casting_enabled? && @assignments.any? %>
    <div class="max-w-4xl mx-auto px-4 py-8">
      <h2 class="text-xl font-semibold text-gray-900 mb-4">Cast</h2>
      <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-4">
        <% @assignments.each do |assignment| %>
          <% assignable = assignment.assignable %>
          <% next unless assignable %>

          <% has_public_profile = assignable.respond_to?(:public_profile_enabled?) ? assignable.public_profile_enabled? : assignable.public_profile_enabled %>
          <% has_public_key = assignable.public_key.present? %>

          <% if has_public_profile && has_public_key %>
            <%= link_to public_profile_path(assignable.public_key), class: "bg-white rounded-lg border border-gray-200 p-4 text-center hover:border-pink-300 transition-colors" do %>
              <% headshot = assignable.safe_headshot_variant(:thumb) %>
              <% if headshot %>
                <%= image_tag headshot, class: "w-16 h-16 rounded-full mx-auto object-cover" %>
              <% else %>
                <div class="w-16 h-16 rounded-full mx-auto bg-gray-200 flex items-center justify-center">
                  <span class="text-gray-500 font-semibold"><%= assignable.respond_to?(:initials) ? assignable.initials : assignable.name.first.upcase %></span>
                </div>
              <% end %>
              <div class="mt-2 font-medium text-gray-900 text-sm"><%= assignable.name %></div>
              <div class="text-xs text-gray-500"><%= assignment.role.name %></div>
            <% end %>
          <% else %>
            <div class="bg-white rounded-lg border border-gray-200 p-4 text-center">
              <% headshot = assignable.safe_headshot_variant(:thumb) rescue nil %>
              <% if headshot %>
                <%= image_tag headshot, class: "w-16 h-16 rounded-full mx-auto object-cover" %>
              <% else %>
                <div class="w-16 h-16 rounded-full mx-auto bg-gray-200 flex items-center justify-center">
                  <span class="text-gray-500 font-semibold"><%= assignable.respond_to?(:initials) ? assignable.initials : assignable.name.first.upcase %></span>
                </div>
              <% end %>
              <div class="mt-2 font-medium text-gray-900 text-sm"><%= assignable.name %></div>
              <div class="text-xs text-gray-500"><%= assignment.role.name %></div>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
  <% end %>

  <!-- Show Links -->
  <% if @show.show_links.any? %>
    <div class="max-w-4xl mx-auto px-4 py-8">
      <h2 class="text-xl font-semibold text-gray-900 mb-4">Links</h2>
      <div class="flex flex-wrap gap-2">
        <% @show.show_links.each do |link| %>
          <%= link_to link.url, target: "_blank", rel: "noopener noreferrer", class: "inline-flex items-center gap-1 px-4 py-2 text-sm font-medium text-pink-700 bg-pink-50 rounded-lg hover:bg-pink-100 transition-colors" do %>
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
            </svg>
            <%= link.display_text %>
          <% end %>
        <% end %>
      </div>
    </div>
  <% end %>
</div>
```

---

## Further Considerations

### 1. Show ID in URL Format
**Decision needed:** Use raw show ID (`/:public_key/153`) or slugified show name/date (`/:public_key/opening-night-2025-03-15`)?

**Recommendation:** Use ID for simplicity. Slugs would require:
- Additional column on shows table
- Slug generation/uniqueness logic
- Handling slug changes

### 2. Past Shows Visibility
**Decision needed:** Should past shows still be visible on public pages, or only upcoming?

**Recommendation:** Show all non-canceled shows but:
- Highlight upcoming shows prominently
- Show past shows in a separate, less prominent section
- Limit past shows displayed (e.g., last 10)

### 3. Production Poster vs Logo
**Decision needed:** The public production page could show the primary poster as hero image, or the production logo. Which is preferred?

**Recommendation:** Priority order:
1. Primary poster (if exists)
2. Production logo (fallback)
3. Initials placeholder (last resort)

---

## Migration Checklist

1. [ ] Generate and run database migrations
2. [ ] Update Production model with validations and callbacks
3. [ ] Update PublicKeyService to check Production uniqueness
4. [ ] Update Show model with visibility method
5. [ ] Update EventTypeSettingsHelper with public_visible_default
6. [ ] Update config/profile_settings.yml with public_visible_default per event type
7. [ ] Add "Public Profile" tab to production edit view
8. [ ] Update productions controller for new params
9. [ ] Add "Public Visibility" box to show edit view
10. [ ] Update shows controller for visibility param
11. [ ] Add routes for production and show public pages
12. [ ] Extend PublicProfilesController
13. [ ] Create production.html.erb view
14. [ ] Create production_show.html.erb view
15. [ ] Generate public keys for existing productions (rake task)
16. [ ] Write specs for new functionality
