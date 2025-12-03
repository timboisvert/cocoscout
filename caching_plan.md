# Comprehensive Caching Plan for CocoScout

Generated: December 3, 2025

## Implementation Status

### ✅ Priority 1 - Completed
1. **DashboardService#generate** - 5-minute cache with production-based key
2. **AuditionCycle#cached_counts** - 2-minute cache for status counts
3. **Cast Card Partial** - Fragment cache with show/production versioning
4. **Show Info Card Partial** - Fragment cache with show versioning
5. **Talent Pool Members List** - Fragment cache with membership versioning

### ✅ Priority 2 - Completed (where applicable)
6. **My Dashboard** - ⚠️ Not cacheable (contains personalized, entity-specific data)
7. **Shoutout Partial** - Fragment cache with context awareness
8. **Roles List** - ⚠️ Not cached (contains interactive drag-drop elements)
9. **Cast Members List** - ⚠️ Not cached (contains interactive drag-drop elements)
10. **Production#cached_roles_count** - 30-minute cache for roles count

### ✅ Priority 3 - Partially Completed
11. **Availability Grid Header** - ⚠️ Not cached (complex hover interactions)
12. **My Shows - Show Row** - ⚠️ Not cached (uses complex @show_assignments structure)
13. **My Availability** - ⚠️ Not cached (real-time availability state)
14. **Audition Request Row** - ⚠️ Not cached (contains countdown timers)
15. **Audition Past Partial** - Fragment cache with audition/production versioning

### ✅ Priority 4 - Model-Level Caching
16. **Person#cached_card_data / Person#cached_profile_data** - 1-hour cache with automatic invalidation
17. **Group#cached_card_data / Group#cached_profile_data** - 1-hour cache with automatic invalidation
18. **User Accessible Productions** - ⚠️ Deferred (depends on Current.organization thread-local)
19. **TalentPool#cached_member_counts** - 10-minute cache for member counts
20. **Organization#cached_directory_counts** - 10-minute cache for people/groups counts

### ✅ Priority 5 - Aggregations
21. **Navigation Badge Counts** - ⚠️ Deferred (needs NavigationCacheService design)
22. **Calendar Event Data** - ⚠️ Deferred (complex date aggregations)
23. **Questionnaire#cached_response_stats** - 5-minute cache for response statistics
24. **Location Usage Summary** - ⚠️ Deferred
25. **Group Membership List** - ⚠️ Deferred

---

## Cache Invalidation System

A `CacheInvalidation` concern (`app/models/concerns/cache_invalidation.rb`) provides automatic cache invalidation:

### Usage
```ruby
class Person < ApplicationRecord
  include CacheInvalidation
  invalidates_cache :person_card, :person_profile
end
```

### How It Works
- Uses `after_commit` callbacks to invalidate caches after create/update/destroy
- Cache keys follow the pattern: `{cache_name}_{ModelName}_{id}`
- Methods available:
  - `record.invalidate_cache(:cache_name)` - Invalidate specific cache for a record
  - `record.cache_key_for(:cache_name)` - Get the cache key for a record
  - `Model.invalidate_all_caches(:cache_name)` - Invalidate all caches of this type (use sparingly)

### Models with Automatic Invalidation
| Model | Cache Keys Invalidated | Trigger |
|-------|----------------------|---------|
| Person | `:person_card`, `:person_profile` | After save/destroy |
| Group | `:group_card`, `:group_profile` | After save/destroy |
| ProfileHeadshot | Parent's `:person_card`/`:group_card` + `:person_profile`/`:group_profile` | After save/destroy |
| Show | Production dashboard, show info card | After save/destroy |
| Production | Dashboard cache, roles count | After save/destroy |
| AuditionCycle | Counts cache, production dashboard | After save/destroy |
| AuditionRequest | Cycle counts cache, production dashboard | After save/destroy |
| TalentPoolMembership | Talent pool counts | After save/destroy |

---

## Current State
- **Cache Store:** Solid Cache (database-backed, SQLite/PostgreSQL)
- **Max Size:** 256 MB
- **Current Usage:** ~98 entries, 80.7 KB (0.03%)
- **Fragment Caching:** Only in `manage/directory` views (6 cache blocks)

## Executive Summary
This plan identifies 25 caching opportunities across the `/manage` and `/my` sections, prioritized by impact and implementation complexity.

---

## Priority 1: High-Impact, Low-Effort (Implement First)

### 1. Dashboard Service Data Caching
**File:** `app/services/dashboard_service.rb`
**What:** Cache the entire dashboard data hash per production
**Why:** Called on every production dashboard load, involves multiple queries
**Cache Key:** `["dashboard", production.id, production.updated_at]`
**TTL:** 5 minutes (balance freshness vs performance)
**Invalidation:** Production updates, show changes, audition request changes

```ruby
def generate
  Rails.cache.fetch(["dashboard_v1", @production.id, @production.updated_at], expires_in: 5.minutes) do
    {
      open_calls: open_calls_summary,
      upcoming_shows: upcoming_shows,
      availability_summary: availability_summary
    }
  end
end
```

### 2. Audition Cycle Counts
**File:** `app/models/audition_cycle.rb`
**What:** Cache the `counts` method result
**Why:** Four COUNT queries every time dashboard or auditions page loads
**Cache Key:** `["audition_cycle_counts", id, audition_requests.maximum(:updated_at)]`
**TTL:** 2 minutes

```ruby
def counts
  Rails.cache.fetch(["audition_cycle_counts_v1", id, audition_requests.maximum(:updated_at)], expires_in: 2.minutes) do
    {
      unreviewed: audition_requests.where(status: :unreviewed).count,
      undecided: audition_requests.where(status: :undecided).count,
      passed: audition_requests.where(status: :passed).count,
      accepted: audition_requests.where(status: :accepted).count
    }
  end
end
```

### 3. Cast Card Partial (Manage Shows/Casting)
**File:** `app/views/manage/casting/_cast_card.html.erb`
**What:** Fragment cache the entire cast card
**Why:** Rendered multiple times on index pages, contains complex logic
**Cache Key:** `["cast_card_v1", show, show.updated_at, production.roles.cache_key_with_version]`

```erb
<% cache ["cast_card_v1", show, show.updated_at, production.roles.maximum(:updated_at)] do %>
  <!-- existing cast card content -->
<% end %>
```

### 4. Show Info Card Partial
**File:** `app/views/manage/shows/_show_info_card.html.erb`
**What:** Fragment cache the show info display
**Why:** Rendered on show detail pages and cast pages
**Cache Key:** `["show_info_card_v1", show, show.updated_at, compact]`

```erb
<% cache ["show_info_card_v1", show, show.updated_at, compact] do %>
  <!-- existing content -->
<% end %>
```

### 5. Talent Pool Members List
**File:** `app/views/manage/talent_pools/_talent_pool_members_list.html.erb`
**What:** Fragment cache each talent pool member list
**Why:** Rendered for each talent pool, involves member queries and headshot loading
**Cache Key:** `["talent_pool_members_v1", talent_pool, talent_pool.updated_at, current_user_can_manage?(talent_pool.production)]`

```erb
<% cache ["talent_pool_members_v1", talent_pool, talent_pool.updated_at, current_user_can_manage?(talent_pool.production)] do %>
  <!-- existing content -->
<% end %>
```

---

## Priority 2: High-Impact, Medium-Effort

### 6. My Dashboard - Upcoming Shows Section
**File:** `app/views/my/dashboard/index.html.erb`
**What:** Cache each show entity row
**Why:** Complex queries for person's shows across groups
**Cache Key:** `["my_dashboard_show_v1", show, entity, assignment&.updated_at]`

```erb
<% @upcoming_show_entities.each do |item| %>
  <% cache ["my_dashboard_show_v1", item[:show], item[:entity], item[:show].updated_at] do %>
    <!-- show row content -->
  <% end %>
<% end %>
```

### 7. Shoutout Partial
**File:** `app/views/my/shoutouts/_shoutout.html.erb`
**What:** Fragment cache each shoutout
**Why:** Rendered in loops, includes headshot loading and previous versions
**Cache Key:** `["shoutout_v1", shoutout, shoutout.updated_at, context]`

```erb
<% cache ["shoutout_v1", shoutout, shoutout.updated_at, context] do %>
  <!-- existing shoutout content -->
<% end %>
```

### 8. Roles List Partial (Casting)
**File:** `app/views/manage/casting/_roles_list.html.erb`
**What:** Cache the roles list for a show
**Why:** Rendered on casting pages, involves role assignments
**Cache Key:** `["roles_list_v1", show, show.updated_at, production.roles.maximum(:updated_at)]`

### 9. Cast Members List Partial (Casting)
**File:** `app/views/manage/casting/_cast_members_list.html.erb`
**What:** Cache the cast members grid
**Why:** Involves complex member lookups and headshots
**Cache Key:** `["cast_members_list_v1", show, show.updated_at, filter_param]`

### 10. Production Roles Count
**File:** `app/models/production.rb` (add method if not exists)
**What:** Cache roles count per production
**Why:** Used in many places for cast percentage calculations
**Cache Key:** `["production_roles_count_v1", id, roles.maximum(:updated_at)]`
**TTL:** 30 minutes

---

## Priority 3: Medium-Impact Optimizations

### 11. Availability Grid Header (Shows)
**File:** `app/views/manage/availability/index.html.erb`
**What:** Cache the show column headers
**Why:** Static per show, rendered for each column
**Cache Key:** `["availability_show_header_v1", show, show.updated_at]`

### 12. My Shows - Show Row
**File:** `app/views/my/shows/index.html.erb`
**What:** Cache individual show rows in the list
**Why:** Multiple shows rendered, each with entity/assignment lookups
**Cache Key:** `["my_show_row_v1", show, show.updated_at, entity_filter]`

### 13. My Availability - Show Entity Pair
**File:** `app/views/my/availability/` views
**What:** Cache each show/entity availability cell
**Why:** Rendered for each show × entity combination
**Cache Key:** `["availability_pair_v1", show, entity, availability&.status]`

### 14. Audition Request Row (My)
**File:** `app/views/my/audition_requests/index.html.erb`
**What:** Cache each audition request row
**Why:** Includes production info and entity headshots
**Cache Key:** `["my_audition_request_v1", audition_request, audition_request.updated_at]`

### 15. Audition Row (My)
**File:** `app/views/my/auditions/index.html.erb`
**What:** Cache each audition row
**Why:** Includes session info and production data
**Cache Key:** `["my_audition_v1", audition, audition.updated_at]`

---

## Priority 4: Model-Level Caching

### 16. Person/Group Headshot URL
**Files:** `app/models/person.rb`, `app/models/group.rb`
**What:** Cache the headshot variant URL generation
**Why:** `safe_headshot_variant` called repeatedly, Active Storage processing
**Cache Key:** `["headshot_url_v1", model_type, id, profile_headshots.maximum(:updated_at), variant]`
**TTL:** 1 hour

```ruby
def safe_headshot_variant(variant = :medium)
  Rails.cache.fetch(["headshot_url_v1", self.class.name, id, profile_headshots.maximum(:updated_at), variant], expires_in: 1.hour) do
    # existing implementation
  end
end
```

### 17. Production Active Status
**File:** `app/models/production.rb`
**What:** Cache computed active status checks
**Why:** Called for authorization/visibility checks
**TTL:** 5 minutes

### 18. User Accessible Productions
**File:** `app/models/user.rb`
**What:** Cache the list of productions a user can access
**Why:** Queried on every manage page load
**Cache Key:** `["user_productions_v1", id, team_memberships.maximum(:updated_at)]`
**TTL:** 5 minutes

### 19. Talent Pool Member Counts
**File:** `app/models/talent_pool.rb`
**What:** Cache member counts
**Why:** Displayed on talent pool list pages
**Cache Key:** `["talent_pool_counts_v1", id, talent_pool_memberships.maximum(:updated_at)]`

### 20. Organization People/Groups Counts
**File:** `app/models/organization.rb`
**What:** Cache directory totals
**Why:** Used in directory pagination and headers
**Cache Key:** `["org_counts_v1", id, people.maximum(:updated_at), groups.maximum(:updated_at)]`

---

## Priority 5: View-Level Aggregations

### 21. Production Navigation Badge Counts
**What:** Cache unread/pending counts shown in navigation
**Why:** Queried on every page load
**Location:** Create a `NavigationCacheService`
**TTL:** 1 minute

### 22. Calendar Event Data (Manage & My)
**Files:** `manage/shows/calendar.html.erb`, `my/shows/calendar.html.erb`
**What:** Cache calendar JSON data
**Why:** Complex date aggregations
**Cache Key:** `["calendar_data_v1", production_or_person, shows.maximum(:updated_at), month]`

### 23. Questionnaire Response Summary
**File:** Questionnaire views
**What:** Cache response statistics
**Why:** COUNT queries for response rates
**Cache Key:** `["questionnaire_stats_v1", questionnaire.id, questionnaire_responses.maximum(:updated_at)]`

### 24. Location Usage Summary
**File:** `app/models/location.rb`
**What:** Cache upcoming shows/sessions for a location
**Why:** Used in location management views
**Cache Key:** `["location_upcoming_v1", id, Time.current.beginning_of_day]`
**TTL:** 15 minutes

### 25. Group Membership List
**File:** `app/views/my/groups/` views
**What:** Cache group member listings
**Why:** Member lookups with headshots
**Cache Key:** `["group_members_v1", group.id, group.updated_at]`

---

## Implementation Order

### Week 1: Quick Wins
1. ✅ Audition Cycle Counts (#2)
2. ✅ Dashboard Service (#1)
3. ✅ Cast Card Partial (#3)
4. ✅ Show Info Card (#4)
5. ✅ Talent Pool Members (#5)

### Week 2: My Section
6. My Dashboard Shows (#6)
7. Shoutout Partial (#7)
8. My Shows Row (#12)
9. My Audition Request Row (#14)
10. My Audition Row (#15)

### Week 3: Model Caching
11. Headshot URL Caching (#16)
12. User Accessible Productions (#18)
13. Talent Pool Counts (#19)
14. Organization Counts (#20)

### Week 4: Remaining Items
15-25. Remaining items based on usage analytics

---

## Cache Invalidation Strategy

### Touch Callbacks
Add `touch: true` to key associations:
```ruby
# Show model
belongs_to :production, touch: true

# ShowPersonRoleAssignment model
belongs_to :show, touch: true

# AuditionRequest model
belongs_to :audition_cycle, touch: true
```

### Manual Invalidation
For complex invalidation, create a `CacheInvalidationService`:
```ruby
class CacheInvalidationService
  def self.invalidate_production_dashboard(production)
    Rails.cache.delete_matched("dashboard_v1/#{production.id}/*")
  end

  def self.invalidate_show_caches(show)
    Rails.cache.delete_matched("cast_card_v1/#{show.cache_key}/*")
    Rails.cache.delete_matched("show_info_card_v1/#{show.cache_key}/*")
  end
end
```

---

## Monitoring

After implementation, use `rake cache:diagnostics` to track:
- Cache hit rates (add instrumentation)
- Entry growth over time
- Size distribution changes
- Most frequently cached patterns

### Add Cache Instrumentation
```ruby
# config/initializers/cache_instrumentation.rb
ActiveSupport::Notifications.subscribe('cache_read.active_support') do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  if event.payload[:hit]
    Rails.logger.debug "CACHE HIT: #{event.payload[:key]}"
  else
    Rails.logger.debug "CACHE MISS: #{event.payload[:key]}"
  end
end
```

---

## Expected Results

After full implementation:
- **Cache entries:** 5,000-20,000 (depending on usage)
- **Cache size:** 20-80 MB
- **Response time improvement:** 30-50% for dashboard pages
- **Database query reduction:** 40-60% for cached pages
