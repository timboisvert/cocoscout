## Plan: Groups & Ensembles Feature

This plan outlines the user experience for adding Groups & Ensembles functionality to CocoScout, allowing performers to create and manage group entities (bands, duos, troupes, etc.) that can audition, be cast, and respond to questionnaires as single units.

### Core Concepts

**Groups as First-Class Citizens**: Groups exist alongside Person objects as independent entities that can audition, be cast, respond to questionnaires, and declare availability. Groups are not tied to organizations but can be associated with them through auditions or invitations.

**Polymorphic Relationships**: Many existing relationships (casting, audition requests, questionnaire invitations) will become polymorphic to support both Person and Group as "auditionable" or "castable" entities.

**Unified View**: All `/my` section pages show both personal items and group items in a single unified list. Users don't switch contexts - they see everything they're involved in (personally or through their groups) in one place.

### Navigation & Interface

#### Top Right Navigation
- Always shows user's personal name (never switches)
- Dropdown menu includes:
  - Link to "My Profile"
  - Link to "My Groups"
  - Standard account/logout options
- No context switching mechanism - all views are unified

#### URL Structure
- Public profiles: `cocoscout.com/<key>` (works for both people and groups)
- Group management: `/my/groups/:id/edit`
- Group list: `/my/groups`
- All other `/my` pages show unified views (personal + all groups)

#### Unified List Views
- All `/my` section pages (auditions, questionnaires, shows, availability, etc.) display both personal and group items together
- Visual indicator: Group items show small group icon/photo
- Filter dropdown at top of each list: "All", "Personal", "[Group 1 Name]", "[Group 2 Name]", etc.
- Default view shows "All"
- Items belonging to groups clearly distinguishable by icon
- Group name not displayed inline - just the icon indicator

#### Detail Pages
- URL: `/my/auditions/:id`, `/my/questionnaires/:id`, etc. (same for personal and group items)
- Page header indicates ownership: "Green Day's Audition Request" vs "My Audition Request"
- Breadcrumb: "My Auditions > Green Day's Audition for [Production]"
- For group items with View-only access: action buttons disabled with tooltip "You need Write access to edit this"

### Group Creation & Management

#### Creating a Group
- "Create New Group" button on `/my/groups` page
- Full form with fields:
  - Name (required)
  - Photo/headshot (optional)
  - Bio (optional)
  - Email (required)
  - Phone (optional)
  - Website (optional)
  - Social media links (optional)
  - Resume (optional)
- Cannot invite members during creation - only after
- After creation, redirects to group's edit page (`/my/groups/:id/edit`)
- Creator automatically becomes first owner

#### Group Settings/Edit Page (`/my/groups/:id/edit`)

**Basic Info Section:**
- Name, photo, bio, contact details, resume
- Same photo upload/crop flow as person headshots
- Resume uses same attachment/upload flow as person resumes
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
- "Create New Group" button prominent at top
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
- Accessed from `/my/auditions` page
- Form includes "Submitting as:" dropdown with options: user's name + all groups with write access
- Form clearly indicates selected entity
- If submitting as group: form uses group's contact info, name, bio
- Internally tracks which individual submitted on behalf of group
- After submission, request appears in unified `/my/auditions` list with group icon if for a group
- Only members with write access see groups as options in dropdown

#### Audition Invitations
- Invitations appear in unified `/my/auditions` list
- If both user and their group are invited: two separate entries in list
- Each entry clearly shows who was invited (personal or group icon indicator)
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
- Availability page shows separate sections for each entity (personal + each group)
- "Your Availability" section for personal availability
- "[Group Name]'s Availability" section for each group with write access
- Groups declare availability independently of member availability
- No warnings about member conflicts between personal and group schedules
- Anyone with write access can manage group availability
- Calendar view shows all events (personal + groups) on same calendar
- Events visually distinguished by small profile photo/icon of the entity
- Both personal and group availability displayed when viewing shows/events
- Individual member availability irrelevant when group is cast

### Questionnaires

#### Inviting Groups
- Groups appear in questionnaire invitation list alongside individuals
- Visual distinction (icon/badge) indicates group vs individual
- Type-ahead search shows both: "Green Day (group)" and "Jane Greenwood (person)"
- Filter options: "All", "Individuals", "Groups"
- Inviting a group counts as 1 invitee

#### Questionnaire Response
- Invitations appear in unified `/my/questionnaires` list
- If both user and their group are invited: two separate entries in list
- Each entry clearly shows who was invited (personal or group icon indicator)
- Response form includes "Responding as:" dropdown if user has multiple pending invitations (personal + groups)
- Can select which invitation to respond to via dropdown
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
- Resume section: downloadable resume if uploaded
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
- `Group`: name, bio, email, phone, website, social_links, resume (attachment), archived_at, key (for public URL)
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
