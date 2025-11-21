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