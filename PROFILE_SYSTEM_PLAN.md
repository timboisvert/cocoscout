# Enhanced Profile & Group Pages System - Implementation Plan

## Overview

Build a comprehensive, performer-focused profile system supporting all live performance disciplines (theatre, comedy, dance, magic, burlesque, circus, music, etc.) with multiple headshots, video links, structured performance history, training, and skills management. Support both people and groups with the same flexible structure, backward-compatible with existing single-headshot/resume data.

**Critical Design Requirement**: All pages must match existing CocoScout design system and UI patterns from current `/my` pages and public profiles.

---

## Table of Contents

1. [Project Questions & Answers](#project-questions--answers)
2. [Implementation Steps](#implementation-steps)
3. [Design System Consistency Requirements](#design-system-consistency-requirements)
4. [Technical Specifications](#technical-specifications)
5. [Design System Audit Results](#design-system-audit-results)
6. [Recommended Consistency Fixes](#recommended-consistency-fixes)
7. [Implementation Checklist](#implementation-checklist)

---

## Project Questions & Answers

### Q1: Headshot Categories
**Question**: Should headshot categories be predefined (Theatrical, Commercial, Character) or open-ended (user-defined)?

**Answer**: **Open-ended (user-defined)**. While we could suggest common categories, performers work across many disciplines with their own terminology. Let users define categories that make sense for them (e.g., "Comedy", "Dramatic", "Period", "Headshot", "Production Still").

### Q2: Year Ranges
**Question**: For performance history and training, should we support single years, year ranges, or "Present" for ongoing work?

**Answer**: **Support all three formats**:
- Single year: "2023"
- Year range: "2020-2023"
- Ongoing: "2023-Present" (checkbox for "Currently performing/studying")

**Recommendations**:
- Use two integer fields: `year_start` (required) and `year_end` (optional, null = present)
- Add checkbox "Currently performing/studying here" that sets year_end to null
- Display logic: If year_end is null, show "2023-Present"; if year_start == year_end, show "2023"; otherwise show "2020-2023"
- Validation: year_end must be >= year_start if present

### Q3: Mobile Drag-and-Drop
**Question**: How should drag-and-drop work on mobile/touch devices for reordering?

**Answer**: **Hybrid approach** - feature detection:
- **Desktop**: Full SortableJS drag-and-drop with grab handles
- **Mobile (touch devices)**: Show "Move Up ▲" / "Move Down ▼" buttons instead
- Auto-detect touch capability using CSS media queries or JavaScript
- Both interfaces update the same `position` field

**Implementation**:
```erb
<div class="flex items-center gap-2">
  <!-- Desktop drag handle -->
  <div class="hidden md:block cursor-grab" data-sortable-handle>
    <svg><!-- hamburger icon --></svg>
  </div>

  <!-- Mobile up/down buttons -->
  <div class="md:hidden flex flex-col gap-1">
    <button type="button"
            data-action="click->sortable-list#moveUp"
            class="p-1 text-gray-600 hover:text-pink-600">
      ▲
    </button>
    <button type="button"
            data-action="click->sortable-list#moveDown"
            class="p-1 text-gray-600 hover:text-pink-600">
      ▼
    </button>
  </div>

  <!-- Item content -->
  <div class="flex-1"><!-- ... --></div>
</div>
```

### Q4: Reserved Public Keys
**Question**: What public keys should be reserved to prevent conflicts with system routes?

**Answer**: Maintain a comprehensive reserved keys list in `config/reserved_public_keys.yml`:

**Categories**:
- **System Routes**: admin, api, www, cdn, static, assets, uploads
- **App Namespaces**: manage, my, god, auth, sessions, signout, login, signup, signin, signoff, logout
- **Common Pages**: about, contact, help, support, faq, terms, privacy, legal, pricing, features
- **HTTP Methods**: get, post, put, patch, delete, options, head
- **Reserved Words**: user, users, account, accounts, profile, profiles, settings, setting, config, configuration
- **Tech Terms**: app, application, system, dashboard, console, root, index
- **CocoScout Specific**: cocoscout, coco, scout, productions, auditions, shows, casting, questionnaires
- **Status/Meta**: status, health, metrics, monitoring, analytics
- **Plus**: Comprehensive profanity/offensive terms list

### Q5: Performance History Suggestions
**Question**: Should we provide suggested section names or venue/role autocomplete based on common theatre companies/roles?

**Answer**: **Floating help panel approach**:

- Provide suggested section names in a collapsible "Common Sections" help text (Theatre, Musical Theatre, Film, Television, Comedy, etc.)
- Don't autocomplete venues/roles initially - let users enter freely
- Future enhancement: Build autocomplete from existing database entries as the system grows
- Keep it simple and flexible for now - performers know their credits

**Suggested Sections to Display**:
Theatre, Musical Theatre, Film, Television, Web Series, Commercials, Voice-Over, Stand-Up Comedy, Improv, Sketch Comedy, Dance, Music/Concerts, Magic, Circus Arts, Burlesque, Cabaret, Industrial/Corporate, Motion Capture, New Media

### Q6: Character Limits
**Question**: What character limits should we enforce for various fields?

**Answer**: **Soft and hard limits with progressive warnings**:

| Field | Soft Limit | Hard Limit | UI Treatment |
|-------|-----------|-----------|--------------|
| Bio | 500 chars | 2000 chars | Counter at 80%, yellow warning at 90%, red at 95% |
| Performance Title | 100 chars | 200 chars | Counter appears at 80% |
| Performance Role | 50 chars | 100 chars | Counter appears at 80% |
| Performance Venue | 100 chars | 200 chars | Counter appears at 80% |
| Performance Location | 50 chars | 100 chars | Counter appears at 80% |
| Performance Notes | 200 chars | 1000 chars | Counter appears at 80% |
| Training Institution | 100 chars | 200 chars | Counter appears at 80% |
| Training Program | 100 chars | 200 chars | Counter appears at 80% |
| Section Name | 30 chars | 50 chars | Counter appears at 80% |
| Video Title | 50 chars | 100 chars | Counter appears at 80% |
| Custom Skill | 30 chars | 50 chars | Counter appears at 80% |

**UI Implementation**:
- No counter until 80% of soft limit
- At 80-89%: Show gray counter "125/500"
- At 90-94%: Show yellow counter with icon "450/500 ⚠️"
- At 95-99%: Show red counter "475/500 ⚠️"
- At hard limit: Prevent further input, show red "200/200 (maximum)"

---

## Implementation Steps

### Step 0: Create Shared Component Partials (DO FIRST)

Before building the profile system, create reusable component partials to ensure design consistency from day one.

#### Create app/views/shared/_button.html.erb

```erb
<%
  # Shared button component for consistent styling across the app
  #
  # Usage:
  #   <%= render "shared/button", text: "Save Changes", variant: "primary", size: "medium" %>
  #   <%= render "shared/button", text: "Cancel", variant: "secondary", path: root_path %>
  #   <%= render "shared/button", text: "Delete", variant: "danger", size: "small", type: :button %>
  #
  # Parameters:
  #   text (required): Button text
  #   variant: "primary" (default), "secondary", "danger", "ghost"
  #   size: "small", "medium" (default), "large"
  #   type: :submit (default), :button
  #   path: If provided, renders as link_to instead of button
  #   classes: Additional custom classes

  variant ||= "primary"
  size ||= "medium"
  type ||= :submit
  classes ||= ""

  base_classes = "font-medium rounded-md transition-colors inline-flex items-center justify-center"

  variant_classes = case variant
    when "primary"
      "bg-pink-600 text-white hover:bg-pink-700 focus:ring-2 focus:ring-pink-500 focus:ring-offset-2"
    when "secondary"
      "border border-pink-600 text-pink-600 hover:bg-pink-50 focus:ring-2 focus:ring-pink-500 focus:ring-offset-2"
    when "danger"
      "bg-red-600 text-white hover:bg-red-700 focus:ring-2 focus:ring-red-500 focus:ring-offset-2"
    when "ghost"
      "text-pink-600 hover:bg-pink-50 focus:ring-2 focus:ring-pink-500 focus:ring-offset-2"
    else
      "bg-pink-600 text-white hover:bg-pink-700 focus:ring-2 focus:ring-pink-500 focus:ring-offset-2"
  end

  size_classes = case size
    when "small"
      "px-3 py-1.5 text-xs"
    when "medium"
      "px-4 py-2 text-sm"
    when "large"
      "px-5 py-2.5 text-base"
    else
      "px-4 py-2 text-sm"
  end

  all_classes = "#{base_classes} #{variant_classes} #{size_classes} #{classes}".strip
%>

<% if defined?(path) && path.present? %>
  <%= link_to text, path, class: all_classes %>
<% elsif type == :submit %>
  <%= submit_tag text, class: all_classes %>
<% else %>
  <button type="<%= type %>" class="<%= all_classes %>">
    <%= text %>
  </button>
<% end %>
```

#### Create app/views/shared/_section_header.html.erb

```erb
<%
  # Shared section header component with optional collapse and visibility toggle
  #
  # Usage:
  #   <%= render "shared/section_header", title: "Basic Information" %>
  #   <%= render "shared/section_header", title: "Headshots", collapsible: true %>
  #   <%= render "shared/section_header",
  #       title: "Performance History",
  #       collapsible: true,
  #       visibility_toggle: true,
  #       visibility_field_name: "person[profile_visibility_settings][performance_history_visible]",
  #       visibility_checked: true %>
  #
  # Parameters:
  #   title (required): Section title text
  #   collapsible: false (default), true
  #   visibility_toggle: false (default), true
  #   visibility_field_name: Name attribute for visibility checkbox
  #   visibility_checked: true (default), false

  collapsible ||= false
  visibility_toggle ||= false
  visibility_field_name ||= nil
  visibility_checked = true if !defined?(visibility_checked) || visibility_checked.nil?
%>

<div class="bg-gray-50 px-4 py-3 border-b border-gray-200 flex items-center justify-between">
  <div class="flex items-center gap-3">
    <% if collapsible %>
      <button type="button"
              data-action="click->profile-section#toggle"
              class="text-gray-600 hover:text-gray-900 focus:outline-none">
        <svg class="w-5 h-5 transform transition-transform"
             data-profile-section-target="icon"
             fill="none"
             stroke="currentColor"
             viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
        </svg>
      </button>
    <% end %>

    <h3 class="text-md font-semibold text-gray-900 coustard-regular">
      <%= title %>
    </h3>
  </div>

  <% if visibility_toggle && visibility_field_name.present? %>
    <label class="flex items-center gap-2 text-sm text-gray-700 cursor-pointer">
      <input type="hidden" name="<%= visibility_field_name %>" value="0">
      <input type="checkbox"
             name="<%= visibility_field_name %>"
             value="1"
             <%= "checked" if visibility_checked %>
             class="rounded border-gray-300 text-pink-600 focus:ring-pink-500">
      <span>Show on profile</span>
    </label>
  <% end %>
</div>
```

#### Create app/views/shared/_badge.html.erb

```erb
<%
  # Shared badge/pill component for consistent tag/label styling
  #
  # Usage:
  #   <%= render "shared/badge", text: "Active", color: "pink" %>
  #   <%= render "shared/badge", text: "Pending", color: "yellow" %>
  #   <%= render "shared/badge", text: "Skills", color: "gray" %>
  #
  # Parameters:
  #   text (required): Badge text
  #   color: "pink" (default), "blue", "green", "red", "yellow", "gray"

  color ||= "gray"

  color_classes = case color
    when "pink"
      "bg-pink-50 text-pink-700 ring-pink-600/10"
    when "blue"
      "bg-blue-50 text-blue-700 ring-blue-600/10"
    when "green"
      "bg-green-50 text-green-700 ring-green-600/10"
    when "red"
      "bg-red-50 text-red-700 ring-red-600/10"
    when "yellow"
      "bg-yellow-50 text-yellow-700 ring-yellow-600/20"
    when "gray"
      "bg-gray-50 text-gray-700 ring-gray-600/10"
    else
      "bg-gray-50 text-gray-700 ring-gray-600/10"
  end
%>

<span class="inline-flex items-center rounded-md px-2 py-1 text-xs font-medium ring-1 ring-inset <%= color_classes %>">
  <%= text %>
</span>
```

### Step 1: Create Database Migrations and Models

Create new profile data models (additive only, no changes to existing fields):

#### ProfileHeadshot Model
- **Polymorphic**: `profileable_type`, `profileable_id` (person/group)
- **Fields**:
  - `category`: string (user-defined: "Theatrical", "Commercial", "Character", etc.)
  - `is_primary`: boolean (default: false)
  - `position`: integer (for drag-and-drop ordering)
  - `image`: ActiveStorage attachment
- **Validations**:
  - Max 10 headshots per person/group
  - Only one primary per profileable
  - Image content type validation (jpg, png, webp)
- **Associations**:
  ```ruby
  belongs_to :profileable, polymorphic: true
  has_one_attached :image
  ```

#### ProfileVideo Model
- **Polymorphic**: `profileable_type`, `profileable_id` (person/group)
- **Fields**:
  - `title`: string (max 100 chars)
  - `url`: string (YouTube/Vimeo URL)
  - `video_type`: enum [:youtube, :vimeo, :other] (default: :other)
  - `position`: integer
- **Validations**:
  - URL format validation
  - Auto-detect video type from URL
- **Associations**:
  ```ruby
  belongs_to :profileable, polymorphic: true
  ```

#### PerformanceCredit Model
- **Polymorphic**: `profileable_type`, `profileable_id` (person/group)
- **Fields**:
  - `section_name`: string (user-defined: "Theatre", "Comedy", "Dance", etc.)
  - `title`: string (show/performance name, max 200 chars)
  - `venue`: string (theater/venue name, max 200 chars)
  - `location`: string (city/state, max 100 chars)
  - `role`: string (optional, max 100 chars)
  - `year_start`: integer
  - `year_end`: integer (null = ongoing/present)
  - `notes`: text (optional, max 1000 chars)
  - `link_url`: string (optional, link to video/review/etc)
  - `position`: integer
- **Validations**:
  - year_start required
  - year_end >= year_start if present
  - year_start/end between 1900 and current_year + 5
- **Associations**:
  ```ruby
  belongs_to :profileable, polymorphic: true
  ```

#### TrainingCredit Model
- **Belongs to**: `person_id` (NOT polymorphic - people only)
- **Fields**:
  - `institution`: string (school/company name, max 200 chars)
  - `program`: string (degree/program/workshop name, max 200 chars)
  - `location`: string (city/state, max 100 chars)
  - `year_start`: integer
  - `year_end`: integer (null = ongoing)
  - `notes`: text (optional, max 1000 chars)
  - `position`: integer
- **Validations**:
  - institution and program required
  - year validation same as PerformanceCredit
- **Associations**:
  ```ruby
  belongs_to :person
  ```

#### ProfileSkill Model
- **Polymorphic**: `profileable_type`, `profileable_id` (person/group)
- **Fields**:
  - `category`: string (from skills config: "Languages", "Dance", "Music", etc.)
  - `skill_name`: string (from skills config or custom)
- **Validations**:
  - Unique combination of profileable + category + skill_name
- **Associations**:
  ```ruby
  belongs_to :profileable, polymorphic: true
  ```

#### Database Columns to Add
```ruby
# Add to people and groups tables
add_column :people, :profile_visibility_settings, :jsonb, default: {}
add_column :people, :hide_contact_info, :boolean, default: false
add_column :groups, :profile_visibility_settings, :jsonb, default: {}
add_column :groups, :hide_contact_info, :boolean, default: false
```

**Migration Note**: Keep existing `headshot` and `resume` ActiveStorage attachments on Person/Group models for backward compatibility.

### Step 2: Create Skills Configuration System

#### Create config/profile_skills.yml

Structure covering all performance disciplines:

```yaml
languages:
  - English
  - Spanish
  - French
  - Mandarin
  - German
  - Italian
  - Japanese
  - ASL (American Sign Language)
  - BSL (British Sign Language)
  - Russian
  - Portuguese
  - Arabic
  - Korean
  - Hindi

accents_dialects:
  - British RP
  - Cockney
  - Irish
  - Scottish
  - Southern American
  - New York
  - Boston
  - Chicago
  - Texas
  - California Valley
  - Australian
  - New Zealand
  - South African
  - Russian
  - French
  - German
  - Italian
  - Spanish (Spain)
  - Spanish (Latin America)
  - Indian

dance_styles:
  - Ballet
  - Tap
  - Jazz
  - Hip-Hop
  - Contemporary
  - Modern
  - Ballroom
  - Latin
  - Swing
  - Salsa
  - Tango
  - Waltz
  - Aerial Silks
  - Pole Dancing
  - Belly Dance
  - Irish Step Dance
  - Flamenco
  - Breakdancing
  - Pointe
  - Lyrical

musical_instruments:
  - Piano
  - Guitar (Acoustic)
  - Guitar (Electric)
  - Bass Guitar
  - Drums
  - Violin
  - Viola
  - Cello
  - Double Bass
  - Trumpet
  - Trombone
  - Saxophone
  - Clarinet
  - Flute
  - Oboe
  - French Horn
  - Tuba
  - Harmonica
  - Accordion
  - Banjo
  - Ukulele
  - Harp
  - Keyboard/Synth

voice_types:
  - Soprano
  - Mezzo-Soprano
  - Alto
  - Tenor
  - Baritone
  - Bass
  - Countertenor
  - Beatbox
  - Voice Acting
  - Voice-Over
  - Narration
  - Character Voices
  - Singing (Pop)
  - Singing (Rock)
  - Singing (Jazz)
  - Singing (Classical)
  - Singing (Musical Theatre)
  - Rapping/MC

comedy_styles:
  - Stand-Up Comedy
  - Improv (Short-form)
  - Improv (Long-form)
  - Sketch Comedy
  - Musical Comedy
  - Character Work
  - Physical Comedy
  - One-Person Show
  - Clowning
  - Satire
  - Dark Comedy
  - Observational
  - Storytelling

magic_illusion:
  - Close-Up Magic
  - Stage Magic
  - Mentalism
  - Sleight of Hand
  - Card Magic
  - Coin Magic
  - Escapology
  - Grand Illusions
  - Street Magic
  - Pickpocketing

circus_physical:
  - Juggling
  - Acrobatics
  - Aerial Silks
  - Aerial Hoop/Lyra
  - Trapeze (Static)
  - Trapeze (Flying)
  - Tightrope Walking
  - Stilt Walking
  - Fire Performance
  - Fire Eating
  - Fire Breathing
  - Sword Swallowing
  - Contortion
  - Hand Balancing
  - Partner Acrobatics
  - Tumbling
  - Unicycling

combat_movement:
  - Stage Combat (Unarmed)
  - Stage Combat (Rapier & Dagger)
  - Stage Combat (Broadsword)
  - Stage Combat (Quarterstaff)
  - Stage Combat (Knife)
  - Stage Combat (Smallsword)
  - Stunt Work
  - Parkour
  - Martial Arts (General)
  - Martial Arts (Karate)
  - Martial Arts (Kung Fu)
  - Martial Arts (Taekwondo)
  - Martial Arts (Judo)
  - Martial Arts (Brazilian Jiu-Jitsu)
  - Boxing
  - Fencing
  - Historical Combat
  - Wrestling

technical_skills:
  - Puppetry
  - Hand Puppets
  - Rod Puppets
  - Shadow Puppets
  - Marionettes
  - Bunraku
  - Mime
  - Clowning
  - Mask Work
  - Commedia dell'arte
  - Physical Theatre
  - Devised Theatre
  - Ventriloquism
  - Storytelling
  - Object Manipulation

special_skills:
  - Driving (Manual)
  - Driving (Automatic)
  - Motorcycle
  - Bicycle Tricks
  - Horseback Riding
  - Swimming
  - Scuba Diving
  - Roller Skating
  - Ice Skating
  - Skiing
  - Snowboarding
  - Rock Climbing
  - Archery
  - Shooting (Firearms)
  - Yoga
  - Pilates
  - Sign Language Interpretation
  - Whistling
  - Sewing/Costume Making
  - Makeup Artistry
  - Hair Styling
  - Barbering
  - Bartending
  - Cooking
  - Baking
```

#### Create app/services/profile_skills_service.rb

```ruby
class ProfileSkillsService
  def self.all_categories
    skills_config.keys.map(&:to_s)
  end

  def self.skills_for_category(category)
    skills_config[category.to_sym] || []
  end

  def self.all_skills
    skills_config.values.flatten.sort
  end

  def self.valid_skill?(category, skill_name)
    skills_for_category(category).include?(skill_name)
  end

  def self.suggested_sections
    [
      "Theatre",
      "Musical Theatre",
      "Film",
      "Television",
      "Web Series",
      "Commercials",
      "Voice-Over",
      "Stand-Up Comedy",
      "Improv",
      "Sketch Comedy",
      "Dance",
      "Music/Concerts",
      "Magic",
      "Circus Arts",
      "Burlesque",
      "Cabaret",
      "Industrial/Corporate",
      "Motion Capture",
      "New Media"
    ]
  end

  private

  def self.skills_config
    @skills_config ||= YAML.load_file(Rails.root.join('config', 'profile_skills.yml')).deep_symbolize_keys
  end
end
```

### Step 3: Create Stimulus Controllers

Create JavaScript controllers for interactive profile editing features:

#### app/javascript/controllers/profile_section_controller.js

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "icon"]

  toggle() {
    this.contentTarget.classList.toggle("hidden")
    this.iconTarget.classList.toggle("rotate-180")
  }
}
```

#### app/javascript/controllers/sortable_list_controller.js

```javascript
import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static targets = ["list"]

  connect() {
    this.sortable = Sortable.create(this.listTarget, {
      handle: "[data-sortable-handle]",
      animation: 150,
      onEnd: this.updatePositions.bind(this)
    })
  }

  disconnect() {
    if (this.sortable) {
      this.sortable.destroy()
    }
  }

  updatePositions(event) {
    const items = this.listTarget.querySelectorAll("[data-position]")
    items.forEach((item, index) => {
      const input = item.querySelector("input[name*='[position]']")
      if (input) {
        input.value = index
      }
    })
  }

  moveUp(event) {
    const item = event.target.closest("[data-position]")
    const prev = item.previousElementSibling
    if (prev) {
      item.parentNode.insertBefore(item, prev)
      this.updatePositions()
    }
  }

  moveDown(event) {
    const item = event.target.closest("[data-position]")
    const next = item.nextElementSibling
    if (next) {
      item.parentNode.insertBefore(next, item)
      this.updatePositions()
    }
  }
}
```

### Step 4: Update Model Associations

Add to Person and Group models:

```ruby
# app/models/person.rb
class Person < ApplicationRecord
  has_many :profile_headshots, as: :profileable, dependent: :destroy
  has_many :profile_videos, as: :profileable, dependent: :destroy
  has_many :performance_credits, as: :profileable, dependent: :destroy
  has_many :training_credits, dependent: :destroy
  has_many :profile_skills, as: :profileable, dependent: :destroy

  # Backward compatibility helpers
  def primary_headshot
    profile_headshots.find_by(is_primary: true) || profile_headshots.first
  end

  def display_headshots
    if profile_headshots.any?
      profile_headshots.order(:position)
    elsif headshot.attached?
      [OpenStruct.new(image: headshot, category: "Primary", is_primary: true)]
    else
      []
    end
  end

  def display_resume
    resume # Existing ActiveStorage attachment
  end

  def performance_credits_visible?
    profile_visibility_settings.dig("performance_history_visible") != false
  end

  def training_credits_visible?
    profile_visibility_settings.dig("training_visible") != false
  end

  def profile_skills_visible?
    profile_visibility_settings.dig("skills_visible") != false
  end
end

# app/models/group.rb - Similar helpers, minus training_credits
```

### Step 5: Build Enhanced Profile Edit Page

Update `/my/profile/edit` with collapsible sections matching the design system.

### Step 6: Update Public Profile Views

Enhance `app/views/public_profiles/person.html.erb` and `app/views/public_profiles/group.html.erb` with new profile data.

---

## Design System Consistency Requirements

### Core Design Tokens

**Colors**
- Primary: `pink-600` (#EC4899) for CTAs and active states
- Primary Hover: `pink-700` for button hovers
- Text Primary: `gray-900` (#111827) for headings
- Text Secondary: `gray-700` (#374151) for body text
- Text Tertiary: `gray-500` (#6B7280) for muted text
- Border: `gray-200` (#E5E7EB) for card borders
- Border Input: `gray-300` for form inputs
- Background: White (#FFFFFF)
- Background Secondary: `gray-50` (#F9FAFB) for section headers

**Typography**
- Font Family (Headers): `coustard-regular` (custom branding font)
- Font Family (Body): Default Sans-Serif
- H1: `text-4xl font-bold coustard-regular`
- H2: `text-2xl font-bold coustard-regular`
- H3: `text-xl font-semibold`
- H4: `text-lg font-semibold coustard-regular`
- Body: `text-sm text-gray-700`
- Small: `text-xs text-gray-500`

**Spacing**
- Section Margins: `mb-6` between major sections
- Card Padding: `p-6` for card content
- Compact Padding: `p-4` for smaller cards
- Form Element Padding: `px-3 py-2` for inputs
- Button Padding (Medium): `px-4 py-2`
- Gap Between Elements: `gap-3` or `gap-4`

**Borders & Rounding**
- Cards: `border border-gray-200 rounded-lg`
- Buttons: `rounded-md`
- Inputs: `border-gray-300 rounded-md`
- Avatars: `rounded-lg` (not fully rounded)
- Badges: `rounded-md`

**Focus States**
- Standard: `focus:outline-none focus:ring-2 focus:ring-pink-500 focus:border-pink-500`
- With Offset: `focus:ring-2 focus:ring-pink-500 focus:ring-offset-2`

---

## Technical Specifications

### Reserved Public Keys

Store in `config/reserved_public_keys.yml`:

```yaml
# System routes
- admin
- api
- www
- cdn
- static
- assets
- uploads

# App namespaces
- manage
- my
- god
- auth
- sessions
- signout
- login
- signup
- signin
- signoff
- logout

# Common pages
- about
- contact
- help
- support
- faq
- terms
- privacy
- legal
- pricing
- features

# HTTP methods
- get
- post
- put
- patch
- delete
- options
- head

# Reserved words
- user
- users
- account
- accounts
- profile
- profiles
- settings
- setting
- config
- configuration

# Tech terms
- app
- application
- system
- dashboard
- console
- root
- index

# CocoScout specific
- cocoscout
- coco
- scout
- productions
- auditions
- shows
- casting
- questionnaires

# Status/Meta
- status
- health
- metrics
- monitoring
- analytics

# Add comprehensive profanity/offensive terms list
```

---

## Design System Audit Results

### Consistent Patterns Found ✅

**Pink Brand Color**: Consistent use of `pink-500`, `pink-600`, `pink-700` for primary actions, active states, and branding throughout all views.

**Card-Based Layout**: Uniform use of white cards with `border border-gray-200 rounded-lg` pattern across the application.

**Spacing Hierarchy**: Consistent use of `mb-4`, `mb-6`, `p-4`, `p-6` for vertical rhythm and padding.

**Coustard Typography**: Headers consistently use `coustard-regular` font class for brand identity.

**Badge System**: Well-defined color-coded badges using `ring-1 ring-inset` pattern with semantic colors (pink/blue/green/red/yellow).

**Avatar Sizing**: Consistent sizing patterns (`w-12 h-12`, `w-20 h-20`, `w-32 h-32`) with `rounded-lg` rounding.

**Responsive Grids**: Standard responsive grid patterns (`grid-cols-1 md:grid-cols-2 lg:grid-cols-3`).

### Inconsistencies Identified ⚠️

#### High Priority Issues

**1. Form Input Borders**: Mixed use of `border-gray-300` and `border-gray-400`
- **Recommendation**: Standardize on `border-gray-300` everywhere
- **Files affected**: Multiple form views across manage/ and my/ directories

**2. Button Padding Variants**: Multiple padding combinations found
- `px-4 py-2 text-sm` (most common)
- `px-3.5 py-2.5 text-base`
- `px-3 py-1.5 text-xs`
- `px-5 py-2.5 text-base`
- **Recommendation**: Create size variants (small/medium/large) in shared button component

**3. File Input Styling**: Two different styles found
- Pink-50 style: `file:bg-pink-50 file:text-pink-700`
- Pink-500 style: `file:bg-pink-500 file:text-white`
- **Recommendation**: Standardize on pink-500 style (matches primary button)

**4. Gray vs Slate Color Scale**: Some pages use `text-slate-*` instead of `text-gray-*`
- **Recommendation**: Migrate all `slate-*` to `gray-*` for consistency

#### Medium Priority Issues

**5. Card Hover States**: Inconsistent hover effects
- Some use `hover:border-gray-400`
- Others use `hover:border-pink-400`
- Some add `hover:shadow-sm`
- **Recommendation**: Interactive cards get pink hover, info cards stay static

**6. Section Headers**: Inconsistent typography hierarchy
- Some use `text-lg font-semibold`
- Others use `text-md font-semibold coustard-regular`
- **Recommendation**: Standardize section headers with shared component

**7. Badge Ring Styles**: Some badges use `ring-inset`, others don't
- **Recommendation**: Always use `ring-1 ring-inset` pattern

**8. Focus Ring Consistency**: Mixed explicit and implicit focus ring sizing
- **Recommendation**: Always specify `focus:ring-2` explicitly

#### Low Priority Issues

**9. Empty State Styling**: Color and size variations for empty states
- **Recommendation**: Create shared empty_state component

**10. Transition Classes**: Mix of `transition-all` and specific `transition-colors`
- **Recommendation**: Use specific transitions for better performance

**11. Link Underlines**: Inconsistent usage of underlines on text links
- **Recommendation**: Establish pattern (underline for body text links, no underline for nav)

**12. Spacing Approaches**: Mix of `space-y-*` utilities and individual `mb-*` classes
- **Recommendation**: Prefer `space-y-*` for consistent vertical rhythm

**13. Avatar Placeholder Styles**: Minor variations in placeholder background colors
- **Recommendation**: Standardize on `bg-pink-100 text-pink-600`

**14. Shadow Usage**: Shadows mostly absent, no clear pattern when used
- **Recommendation**: Define when to use `shadow-sm` vs none

**15. Form Label Formatting**: Inconsistent weight and sizing
- **Recommendation**: Standardize as `text-sm font-medium text-gray-700 mb-1`

---

## Recommended Consistency Fixes

### Phase 1: High Priority (Do Before Profile System)

#### 1. Create Shared Component Partials ✅
**Status**: Defined in Step 0
- `app/views/shared/_button.html.erb`
- `app/views/shared/_section_header.html.erb`
- `app/views/shared/_badge.html.erb`

#### 2. Standardize Form Input Borders
**Action**: Search and replace across all form views
```erb
# BEFORE (inconsistent)
border-gray-400
border-gray-300

# AFTER (standardized)
border-gray-300
```
**Standard form input class**:
```erb
class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-pink-500 focus:border-pink-500"
```

#### 3. Standardize File Upload Inputs
**Action**: Update all file inputs to use pink-500 style
```erb
class="block w-full text-sm text-gray-500
       file:mr-4 file:py-2 file:px-4
       file:rounded-md file:border-0
       file:text-sm file:font-medium
       file:bg-pink-500 file:text-white
       hover:file:bg-pink-600"
```

#### 4. Fix Gray vs Slate
**Action**: Global search and replace
- `text-slate-*` → `text-gray-*`
- `bg-slate-*` → `bg-gray-*`
- `border-slate-*` → `border-gray-*`

#### 5. Standardize Form Labels
**Action**: Update all form labels
```erb
<%= f.label :field_name, "Label Text", class: "block text-sm font-medium text-gray-700 mb-1" %>
```

### Phase 2: Medium Priority (During Profile System Build)

#### 6. Replace Button Classes with Shared Component
**Action**: As you touch each view, replace inline button classes with:
```erb
<%= render "shared/button", text: "Save", variant: "primary", size: "medium" %>
```

#### 7. Replace Section Headers with Shared Component
**Action**: Replace ad-hoc headers with:
```erb
<%= render "shared/section_header", title: "Section Name", collapsible: true %>
```

#### 8. Standardize Card Hover States
**Interactive cards** (clickable):
```erb
class="border border-gray-200 rounded-lg p-4 hover:border-pink-400 hover:shadow-sm transition-colors cursor-pointer"
```

**Info cards** (non-clickable):
```erb
class="border border-gray-200 rounded-lg p-4"
```

#### 9. Standardize Avatar Styles
**Avatar images**:
```erb
class="w-12 h-12 rounded-lg object-cover"
```

**Avatar placeholders**:
```erb
class="w-12 h-12 rounded-lg bg-pink-100 text-pink-600 font-bold flex items-center justify-center"
```

### Phase 3: Low Priority (Future Cleanup)

#### 10. Create Empty State Component
```erb
# app/views/shared/_empty_state.html.erb
<div class="text-center py-12">
  <p class="text-gray-500 text-sm"><%= message %></p>
  <% if defined?(link_text) && defined?(link_path) %>
    <%= link_to link_text, link_path, class: "text-pink-600 hover:text-pink-700 text-sm underline mt-2 inline-block" %>
  <% end %>
</div>
```

#### 11. Replace transition-all
**Action**: For better performance, use specific transitions
- Color changes: `transition-colors`
- Opacity: `transition-opacity`
- Transform: `transition-transform`
- Multiple: `transition-[colors,transform]`

#### 12. Standardize Link Styles
**Body text links**:
```erb
class="text-pink-600 hover:text-pink-700 underline"
```

**Navigation links**:
```erb
class="text-pink-600 hover:text-pink-700"
```

#### 13. Implement Consistent Spacing
**Action**: Prefer `space-y-*` utilities over individual margins
```erb
# BEFORE
<div>
  <div class="mb-4">Item 1</div>
  <div class="mb-4">Item 2</div>
  <div class="mb-4">Item 3</div>
</div>

# AFTER
<div class="space-y-4">
  <div>Item 1</div>
  <div>Item 2</div>
  <div>Item 3</div>
</div>
```

---

## Implementation Checklist

### Pre-Development
- [ ] **Create shared component partials** (button, section_header, badge, empty_state)
- [ ] **Apply high-priority consistency fixes** (form inputs, file inputs, gray/slate)
- [ ] **Create config/profile_skills.yml** with comprehensive skill categories
- [ ] **Create config/reserved_public_keys.yml** with system reserved keys

### Database & Models
- [ ] Create ProfileHeadshot migration and model
- [ ] Create ProfileVideo migration and model
- [ ] Create PerformanceCredit migration and model
- [ ] Create TrainingCredit migration and model
- [ ] Create ProfileSkill migration and model
- [ ] Add profile_visibility_settings and hide_contact_info to people/groups
- [ ] Create ProfileSkillsService
- [ ] Update Person model with associations and helpers
- [ ] Update Group model with associations and helpers

### JavaScript Controllers
- [ ] Create profile_section_controller.js (collapse/expand)
- [ ] Create sortable_list_controller.js (drag-and-drop with SortableJS)
- [ ] Create headshot_manager_controller.js (upload, categorize, set primary)
- [ ] Create credit_form_controller.js (inline add/edit credits)
- [ ] Create skill_selector_controller.js (category tabs, checkbox grid)
- [ ] Create public_key_preview_controller.js (live URL preview)

### Views - Profile Edit
- [ ] Update My::ProfileController#edit action
- [ ] Rebuild /my/profile/edit with 8 collapsible sections
- [ ] Add headshots upload/management interface
- [ ] Add videos/reels link management
- [ ] Add traditional resume upload section
- [ ] Add performance history section with user-defined categories
- [ ] Add training & education section
- [ ] Add skills & talents multi-select interface
- [ ] Add public key management with preview

### Views - Public Profiles
- [ ] Update app/views/public_profiles/person.html.erb
  - Hero section with primary headshot
  - Additional headshots gallery
  - Videos section with embeds
  - Performance history grouped by section
  - Training & education list
  - Skills & talents by category
  - Resume download button
- [ ] Update app/views/public_profiles/group.html.erb
  - Similar structure to person profile
  - Skip training section
  - Add members roster

### Views - Groups
- [ ] Update My::Groups edit page with profile sections
- [ ] Add performance history toggle (off by default for groups)
- [ ] Add headshots, videos, skills sections

### Testing & QA
- [ ] Manual testing: Desktop profile edit page
- [ ] Manual testing: Mobile responsive profile edit
- [ ] Manual testing: Drag-and-drop on desktop
- [ ] Manual testing: Up/down buttons on mobile
- [ ] Manual testing: Public profile view (person)
- [ ] Manual testing: Public profile view (group)
- [ ] Manual testing: Character limit warnings
- [ ] Manual testing: Public key validation
- [ ] Manual testing: Backward compatibility (old headshot/resume display)

### Documentation
- [ ] Update user guide with profile enhancement features
- [ ] Document shared component usage for team
- [ ] Create design system reference doc

---

## Notes

- **Additive Changes Only**: All new models are additive - no breaking changes to existing schema
- **Backward Compatible**: Existing headshot/resume attachments remain functional
- **Graceful Degradation**: Public profiles fall back to old data if new data doesn't exist
- **Mobile First**: Hybrid drag-drop approach ensures usability on all devices
- **Extensible Skills**: Skills system easily expanded via YAML configuration
- **Character Limits**: Soft limits with warnings, hard limits prevent submission
- **Reserved Keys**: Prevent system route conflicts and profanity
- **Design Consistency**: All new pages match existing CocoScout patterns exactly

---

**Last Updated**: November 21, 2025
**Status**: Planning phase - ready for implementation
**Next Steps**: Create shared component partials, then begin database migrations