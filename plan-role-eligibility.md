Plan: Role Eligibility + Cast Vacancy System
Summary: Restricted roles limit who can be cast. Vacancies (from drop-outs or unfilled roles) create tickets that producers manage. Eligible people can be invited to claim roles via tokenized links. First-claim wins. Notifications keep producers informed.

Phase 1: Role Eligibility
Migration: AddRestrictedToRoles – Add restricted:boolean default:false to roles

Migration: CreateRoleEligibilities – role_id:references, person_id:references, unique composite index

RoleEligibility model – belongs_to :role, belongs_to :person

Update Role model – Add has_many :role_eligibilities and has_many :eligible_people. Add eligible_assignees(talent_pool_ids) returning all talent pool members (if unrestricted) or only eligible people (if restricted).

Update roles form – Toggle + people-picker for restricted roles

Update casting panel – Lock icon on restricted roles, filter draggable talent by eligibility

Phase 2: Vacancy System
Migration: CreateRoleVacancies – show_id:references, role_id:references, vacated_by_id:integer (nullable), vacated_at:datetime, reason:text, status:string default:'open', filled_by_id:integer, filled_at:datetime, closed_at:datetime, closed_by_id:integer, created_by_id:integer (for manual creation)

Migration: CreateRoleVacancyInvitations – role_vacancy_id:references, person_id:references, token:string (indexed, unique), invited_at:datetime, claimed_at:datetime, email_subject:string, email_body:text

RoleVacancy model – Associations, scopes (open, filled, closed), auto-close callback when show starts

RoleVacancyInvitation model – Associations, before_create generates token via SecureRandom.urlsafe_base64, scope pending

"I can't make it" flow – Button on my/shows/:id opens modal, creates vacancy with vacated_by, notifies producers

Manual vacancy creation – On casting page, "Create vacancy" option for unfilled roles, creates vacancy with created_by (no vacated_by)

Production dashboard vacancies – New section on productions/show with badge count, list of open vacancies

Vacancies index page – /manage/productions/:id/vacancies with tabs (Open/Filled/Closed)

Vacancy indicator on casting – Warning badge on roles with open vacancy in casting views

Vacancy detail page – /manage/productions/:id/vacancies/:id – show info, unassign button, "Invite to claim" UI

Invite UI – Checkbox list: eligible people first (highlighted), then other talent pool members. Editable subject/body. Bulk send.

RoleVacancyInvitationMailer – Email with tokenized claim link, show details, role info

Claim page – /claim/:token – Shows role/show, "Claim" button. On claim: assigns role, updates vacancy to filled, notifies producers, invalidates other invitations' claim ability.

Talent-side visibility – Pending invitations on my/dashboard and my/shows/:id

Auto-close job – Recurring job closes open vacancies when show date_and_time passes

Phase 3: Team Notification Preferences
Migration: AddNotificationsEnabledToTeamMemberships – notifications_enabled:boolean (null = use default)

Update TeamMembership model – notifications_enabled? returns explicit value or role-based default (owner/manager = true, viewer = false)

Update team UI – Notification toggle per member

VacancyNotificationJob – Emails team members with notifications enabled on vacancy create/fill

Implementation Order
Phase 1 (eligibility) first – foundation for Phase 2
Phase 2 core (vacancies, invitations, claim flow)
Phase 2 UI (dashboard, casting indicators, talent-side views)
Phase 3 (notifications) – can be done in parallel with Phase 2 UI