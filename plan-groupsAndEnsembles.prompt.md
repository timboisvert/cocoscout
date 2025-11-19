## Plan: Groups & Ensembles Feature

This plan outlines the user experience for adding Groups & Ensembles functionality to CocoScout, allowing performers to create and manage group entities (bands, duos, troupes, etc.) that can audition, be cast, and respond to questionnaires as single units.

### Core Concepts

**Groups as First-Class Citizens**: Groups exist alongside Person objects as independent entities that can audition, be cast, respond to questionnaires, and declare availability. Groups are not tied to organizations but can be associated with them through auditions or invitations.

**Polymorphic Relationships**: Many existing relationships (casting, audition requests, questionnaire invitations) will become polymorphic to support both Person and Group as "auditionable" or "castable" entities.

**Context Switching**: Users can switch between acting as themselves or as a group they belong to via a top-right navigation dropdown, affecting their view of auditions, questionnaires, and availability.

### Navigation & Context

#### Top Navigation Switcher
- Add dropdown in top-right navigation (where user name currently appears)
- Shows current context name (either person name or group name)
- Dropdown lists: user's person name + all groups they're members of
- Selecting a group switches entire `/my` section to show that group's perspective
- Visual indicator: Name in top-right changes from "Tim Boisvert" to "Green Day" when in group context
- Quick switch back to personal context via same dropdown

#### URL Structure
- Public profiles: `cocoscout.com/<key>` (works for both people and groups)
- Group management: `/my/groups/:id/edit`
- Group list: `/my/groups`
- URLs don't change based on context - context is maintained in session/state

#### Page Behavior in Group Context
- Page titles remain generic ("My Auditions", "My Questionnaires")
- Top-right shows group name instead of person name
- All actions (submitting forms, declaring availability) act on behalf of the group
- No breadcrumb or page-level indicators of context beyond top-right name

### Group Creation & Management

#### Creating a Group
- "Create New Group" option in top-right navigation menu
- Full form with fields:
  - Name (required)
  - Photo/headshot (optional)
  - Bio (optional)
  - Email (required)
  - Phone (optional)
  - Website (optional)
  - Social media links (optional)
- Cannot invite members during creation - only after
- After creation, redirects to group's edit page (`/my/groups/:id/edit`)
- Creator automatically becomes first owner

#### Group Settings/Edit Page (`/my/groups/:id/edit`)

**Basic Info Section:**
- Name, photo, bio, contact details
- Same photo upload/crop flow as person headshots
- Standard form with save button

**Members Section:**
- List of current members with photos, names, and links to their profiles
- Role badges NOT shown publicly, but editable inline by owners/write members
- "Invite Member" button opens modal
- Invite modal: email input fields (multiple), optional role selection dropdown per email
- Creates Person + User for non-existent emails (standard invitation flow)
- If email exists, adds person directly to group
- Remove button visible to members with write/ownership access
- Cannot remove last member (must archive instead)
- Cannot demote last owner (must have at least one owner)

**Notification Settings Section:**
- Checkbox list showing all members
- "Receives notifications for this group" checkbox per member
- Owners automatically checked and cannot uncheck themselves
- Other members can opt themselves out
- All group notifications (audition invites, questionnaire invites, cast assignments) go only to checked members who haven't opted out

**Archive Section:**
- "Archive Group" button at bottom
- Only visible to owners
- Confirmation dialog warns: "This will archive [Group Name]. It will no longer appear in searches or directories. Historical data will be preserved."
- If user is last member: dialog changes to "You are the last member. Leaving will archive this group."
- Archived groups hidden from all listings and searches
- Historical data (past castings, responses) remains intact

#### Group List Page (`/my/groups`)
- Shows all groups user is a member of
- Card layout with group photo, name, member count
- No role badges shown
- No separation between "owned" vs "member of"
- Empty state: "You're not part of any groups yet" with "Create Your First Group" call-to-action
- Archived groups appear normally for owners with "Archived" badge and "Unarchive" button
- Unarchive available to any owner, not just person who archived it

### Member Permissions & Roles

#### Three Permission Levels
- **Owner**: Can edit group profile, manage members, change roles, archive/unarchive, respond to auditions/questionnaires, manage availability
- **Write**: Can edit group profile, respond to auditions/questionnaires, manage availability (cannot manage members or archive)
- **View**: Can see all group data but cannot edit or submit anything

#### Permission Management
- Set after invitation acceptance (not during invitation)
- Inline editing on group settings page by owners/write members
- Must maintain at least one owner at all times
- Owners can remove themselves only if not the last owner

#### Member Removal
- Members can remove themselves from group settings page
- Last member cannot leave - must archive group instead
- Removed members receive email notification
- Historical records where they submitted something remain unchanged
- No "former groups" list - once removed, no longer visible

### Audition & Casting Workflows

#### Audition Request Submission
- Context switcher in audition request form: "Submitting as: [Dropdown: Tim Boisvert / Green Day / The Beatles]"
- Form clearly indicates who's submitting
- If submitting as group: form uses group's contact info, name, bio
- Internally tracks which individual submitted on behalf of group
- All notification-enabled group members see request in their audition list with indicator: "Green Day (group audition)"
- Only members with write access can submit for group

#### Audition Invitations
- Groups appear in invitation lists alongside individuals
- Single response per group (one person with write access responds for all)
- No individual member confirmation needed
- Group acts as single entity - internal coordination assumed

#### Casting
- Cast model becomes polymorphic: `castable_type` (Person/Group) and `castable_id`
- Groups appear in cast management search alongside individuals
- Visual indicator (icon) distinguishes groups from individuals in search/lists
- Casting a group counts as ONE cast member
- If Jane Doe (individual) AND The Duo (her group) both cast: two separate cast entries
- Cast list shows group name only (not member breakdown)
- Clicking group name links to group's public profile
- No hover preview or inline member display

#### Availability Management
- Groups declare availability independently of member availability
- No warnings about member conflicts
- Anyone with write access can manage group availability
- Group availability shown on show/event lists
- Individual member availability irrelevant when group is cast

### Questionnaires

#### Inviting Groups
- Groups appear in questionnaire invitation list alongside individuals
- Visual distinction (icon/badge) indicates group vs individual
- Type-ahead search shows both: "Green Day (group)" and "Jane Greenwood (person)"
- Filter options: "All", "Individuals", "Groups"
- Inviting a group counts as 1 invitee

#### Questionnaire Response
- Context switcher on form: "Responding as: [Dropdown]"
- Can switch between personal and group responses
- Only notification-enabled members receive invitation emails
- Any member with write access can respond for group
- Response tied to group only (not individual who submitted)
- Response list shows group name only
- Response detail page shows group's answers (no submitter indication)

### Directory & Search

#### Directory Display
- Groups and individuals appear in same search results
- Visual indicator (icon) distinguishes groups
- Filter dropdown: "All", "Individuals", "Groups & Ensembles"
- Search autocomplete shows both with clear labels
- Group results have distinct styling or icon

#### Organization Association
- Groups don't belong to organizations but associate with them
- Association happens via:
  - Submitting audition request for org's production
  - Being invited through directory by org admin
- Same approval flow as person invitations
- Once associated, group appears in org's talent directory
- Org managers can see/manage group's castings in their productions

### Profile Pages

#### Person Profile - Groups Section
- Dedicated "Groups & Ensembles" section
- Grid display of group photos with names underneath
- Each is link to group's public profile
- Only shows active groups (archived groups hidden completely)
- Prominent placement (not in bio)

#### Group Profile - Public View (`cocoscout.com/<group-key>`)
- Similar layout to person profiles
- Hero section: group photo, name, bio
- Contact section: email, phone, website, social links
- Members section: grid of member photos with names
- Each member photo links to their personal profile
- Role levels NOT shown publicly
- Shows associated productions/castings (same as person profiles)

#### Group Profile - Member View
- If logged-in user is member with write/ownership access: "Edit Group" button appears
- Button links to `/my/groups/:id/edit`
- View-only members don't see edit button

### Email & Notifications

#### Group Notifications
- All group-related notifications go to members with "receives notifications" checked
- Notification types:
  - Invited to audition
  - Cast in production
  - Invited to questionnaire
  - Added to group
  - Removed from group
  - Role changed
  - Group archived
- Owners automatically on notification list (cannot opt out)
- Other members can opt out via group settings
- Email templates indicate "for Green Day" or similar

#### Invitation Emails
- When inviting someone to group who doesn't exist: standard person/user creation flow
- Email subject: "[Person Name] has invited you to join [Group Name] on CocoScout"
- Shows who invited them, current members, group details
- Accept/Decline buttons
- Decliner notifies inviter
- If email already exists: person added directly to group, receives "You've been added to [Group Name]" email

### Data Model Considerations (High-Level)

#### New Models
- `Group`: name, bio, email, phone, website, social_links, archived_at, key (for public URL)
- `GroupMembership`: group_id, person_id, role (owner/write/view), receives_notifications (boolean), invited_at, accepted_at
- `GroupRole`: Similar to renamed OrganizationRole (formerly UserRole)

#### Polymorphic Associations
- `Cast`: polymorphic `castable` (Person or Group)
- `AuditionRequest`: polymorphic `requestable` (Person or Group)
- `QuestionnaireInvitation`: polymorphic `invitee` (Person or Group)
- `QuestionnaireResponse`: polymorphic `respondent` (Person or Group)
- `ShowAvailability`: polymorphic `available_entity` (Person or Group)

#### Organization Association
- `OrganizationAssociation`: polymorphic `associable` (Person or Group), organization_id

### Further Considerations

1. **Group Types/Categories**: Not implementing initially, but future consideration for "Band", "Duo", "Ensemble", "Troupe" classifications

2. **Privacy Controls**: All profiles public initially, but future consideration for private/unlisted groups

3. **Request to Join**: Not implementing initially - invite-only for now

4. **Group-Level Statistics**: Future consideration for group's audition success rate, shows performed, etc.

5. **Subgroups or Nested Groups**: Not in scope - groups are flat entities

6. **Group Billing/Payment**: Not addressed in this spec - groups don't have separate financial relationships

7. **Transfer Ownership**: Possible workflow where owner can transfer ownership before leaving, but not explicitly required for v1

8. **Multi-Group Actions**: Future consideration for bulk operations across multiple groups user manages

This spec focuses on core functionality to make groups first-class citizens in the platform while maintaining consistency with existing person-based workflows.
