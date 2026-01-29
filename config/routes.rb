# frozen_string_literal: true

Rails.application.routes.draw do
  root "home#index"

  # Utility
  get "/up", to: proc { [ 200, {}, [ "OK" ] ] }

  # Landing page
  get "home/index"

  # New homepage (preview)
  get "/new", to: "home#new_home", as: "new_home"
  get "/new/for-performers", to: "home#new_performers", as: "new_performers"
  get "/new/for-producers", to: "home#new_producers", as: "new_producers"

  # Legal pages
  get "/terms", to: "legal#terms", as: "terms"
  get "/privacy", to: "legal#privacy", as: "privacy"

  # Authentication
  get   "/signup",        to: "auth#signup",          as: "signup"
  post  "/signup",        to: "auth#handle_signup",   as: "handle_signup"
  get   "/signin",        to: "auth#signin",          as: "signin"
  post  "/signin",        to: "auth#handle_signin",   as: "handle_signin"
  get   "/signout",       to: "auth#signout",         as: "signout"
  get   "/password",      to: "auth#password",        as: "password"
  post  "/password",      to: "auth#handle_password", as: "handle_password"
  get   "/reset/:token",  to: "auth#reset",           as: "reset"
  post  "/reset/:token",  to: "auth#handle_reset",    as: "handle_reset"
  get   "/set_password/:token",  to: "auth#set_password",        as: "set_password"
  post  "/set_password/:token",  to: "auth#handle_set_password", as: "handle_set_password"

  # Public organization invite link - anyone can join via this link
  get  "/join/:token", to: "organization_join#show", as: "join_organization"
  post "/join/:token", to: "organization_join#join", as: "do_join_organization"

  # Account
  get   "/account",                       to: "account#show",                as: "account"
  patch "/account",                       to: "account#update"
  patch "/account/email",                 to: "account#update_email",        as: "update_email_account"
  get   "/account/profiles",              to: "account#profiles",            as: "account_profiles"
  post  "/account/profiles",              to: "account#create_profile",      as: "create_profile_account"
  post  "/account/profiles/:id/set_default", to: "account#set_default_profile", as: "set_default_profile_account"
  post  "/account/profiles/:id/archive",  to: "account#archive_profile",     as: "archive_profile_account"
  get   "/account/notifications",         to: "account#notifications",       as: "account_notifications"
  patch "/account/notifications",         to: "account#update_notifications"
  get   "/account/subscription",          to: "account#billing",             as: "account_billing"
  get   "/account/organizations",         to: "account#organizations",       as: "account_organizations"
  delete "/account/organizations/:id/leave", to: "account#leave_organization", as: "leave_organization_account"

  # Superadmin
  scope "/superadmin" do
    get  "/",                   to: "superadmin#index",               as: "superadmin"
    post "/impersonate",        to: "superadmin#impersonate",         as: "impersonate_user"
    get  "/search_users",       to: "superadmin#search_users",        as: "search_users"
    post "/stop_impersonating", to: "superadmin#stop_impersonating",  as: "stop_impersonating_user"
    post "/change_email",       to: "superadmin#change_email",        as: "change_email_user"
    get  "/email_logs",         to: "superadmin#email_logs",          as: "email_logs"
    get  "/email_logs/:id",     to: "superadmin#email_log",           as: "email_log"
    get  "/sms_logs",           to: "superadmin#sms_logs",            as: "sms_logs"
    get  "/sms_logs/:id",       to: "superadmin#sms_log",             as: "sms_log"
    get  "/queue",              to: "superadmin#queue",               as: "queue_monitor"
    get  "/queue/failed",       to: "superadmin#queue_failed",        as: "queue_failed"
    post "/queue/retry/:id",    to: "superadmin#queue_retry",         as: "queue_retry"
    post "/queue/retry_all_failed", to: "superadmin#queue_retry_all_failed", as: "queue_retry_all_failed"
    delete "/queue/job/:id",    to: "superadmin#queue_delete_job",    as: "queue_delete_job"
    delete "/queue/clear_failed", to: "superadmin#queue_clear_failed", as: "queue_clear_failed"
    delete "/queue/clear_pending", to: "superadmin#queue_clear_pending", as: "queue_clear_pending"
    post "/queue/run_recurring/:job_key", to: "superadmin#queue_run_recurring_job", as: "queue_run_recurring_job"
    get "/people", to: "superadmin#people_list", as: "people_list"
    delete "/people/bulk_destroy", to: "superadmin#bulk_destroy_people", as: "bulk_destroy_people"
    delete "/people/suspicious/destroy_all", to: "superadmin#destroy_all_suspicious_people",
                                             as: "destroy_all_suspicious_people"
    get "/people/:id", to: "superadmin#person_detail", as: "person_detail"
    delete "/people/:id", to: "superadmin#destroy_person", as: "destroy_person"
    post "/people/:id/merge", to: "superadmin#merge_person", as: "merge_person"
    get  "/organizations",      to: "superadmin#organizations_list",  as: "organizations_list"
    get  "/organizations/:id",  to: "superadmin#organization_detail", as: "organization_detail"
    get  "/storage",            to: "superadmin#storage",             as: "storage_monitor"
    post "/storage/cleanup_orphans", to: "superadmin#storage_cleanup_orphans", as: "storage_cleanup_orphans"
    post "/storage/cleanup_legacy",  to: "superadmin#storage_cleanup_legacy",  as: "storage_cleanup_legacy"
    post "/storage/migrate_keys",    to: "superadmin#storage_migrate_keys",    as: "storage_migrate_keys"
    post "/storage/cleanup_s3_orphans", to: "superadmin#storage_cleanup_s3_orphans", as: "storage_cleanup_s3_orphans"
    get  "/data",               to: "superadmin#data",                as: "data_monitor"
    get  "/profiles",           to: "superadmin#profiles",            as: "profiles_monitor"
    get  "/cache",              to: "superadmin#cache",               as: "cache_monitor"
    post "/cache/clear",        to: "superadmin#cache_clear",         as: "cache_clear"
    post "/cache/clear_pattern", to: "superadmin#cache_clear_pattern", as: "cache_clear_pattern"
    get  "/email_templates",    to: "superadmin#email_templates",     as: "email_templates"
    get  "/email_templates/new", to: "superadmin#email_template_new", as: "email_template_new"
    post "/email_templates",    to: "superadmin#email_template_create", as: "email_template_create"
    get  "/email_templates/:id/edit", to: "superadmin#email_template_edit", as: "email_template_edit"
    patch "/email_templates/:id", to: "superadmin#email_template_update", as: "email_template_update"
    delete "/email_templates/:id", to: "superadmin#email_template_destroy", as: "email_template_destroy"
    get  "/email_templates/:id/preview", to: "superadmin#email_template_preview", as: "email_template_preview"
    get  "/keys",               to: "superadmin#keys",                as: "keys_monitor"

    # Demo Users
    get    "/demo_users",       to: "superadmin#demo_users",          as: "demo_users"
    post   "/demo_users",       to: "superadmin#demo_user_create",    as: "demo_user_create"
    delete "/demo_users/:id",   to: "superadmin#demo_user_destroy",   as: "demo_user_destroy"

    # Dev tools (development only)
    get  "/dev_tools",                    to: "superadmin#dev_tools",                 as: "dev_tools"
    post "/dev_tools/create_users",       to: "superadmin#dev_create_users",          as: "dev_create_users"
    post "/dev_tools/submit_auditions",   to: "superadmin#dev_submit_auditions",      as: "dev_submit_auditions"
    post "/dev_tools/submit_signups",     to: "superadmin#dev_submit_signups",        as: "dev_submit_signups"
    delete "/dev_tools/delete_signups",   to: "superadmin#dev_delete_signups",        as: "dev_delete_signups"
    delete "/dev_tools/delete_users",     to: "superadmin#dev_delete_users",          as: "dev_delete_users"
  end

  # Pilot user setup (superadmins only)
  get "/pilot", to: "pilot#index", as: "pilot"
  post "/pilot/create_talent", to: "pilot#create_talent", as: "pilot_create_talent"
  post "/pilot/create_producer_user", to: "pilot#create_producer_user", as: "pilot_create_producer_user"
  post "/pilot/create_producer_org", to: "pilot#create_producer_org", as: "pilot_create_producer_org"
  post "/pilot/create_producer_location", to: "pilot#create_producer_location", as: "pilot_create_producer_location"
  post "/pilot/create_producer_production", to: "pilot#create_producer_production",
                                            as: "pilot_create_producer_production"
  post "/pilot/create_producer_talent_pool", to: "pilot#create_producer_talent_pool",
                                             as: "pilot_create_producer_talent_pool"
  post "/pilot/create_producer_show", to: "pilot#create_producer_show", as: "pilot_create_producer_show"
  post "/pilot/create_producer_additional", to: "pilot#create_producer_additional",
                                            as: "pilot_create_producer_additional"
  post "/pilot/resend_invitation", to: "pilot#resend_invitation", as: "pilot_resend_invitation"
  delete "/pilot/reset_talent", to: "pilot#reset_talent", as: "pilot_reset_talent"
  delete "/pilot/reset_producer", to: "pilot#reset_producer", as: "pilot_reset_producer"

  # Respond to an audition request
  get "/a/:token", to: "my/submit_audition_request#entry", as: "submit_audition_request"

  # Short URL for sign-up forms
  get "/s/:code", to: "sign_up_shortlink#show", as: "sign_up_shortlink"

  # Selection interface (under manage namespace)
  scope "/select" do
    get  "/organization",        to: "manage/select#organization",     as: "select_organization"
    post "/organization",        to: "manage/select#set_organization", as: "set_organization"
  end

  # Talent-facing interface
  namespace :my do
    get   "/",                              to: "dashboard#index",          as: "dashboard"
    post  "/dismiss_onboarding",            to: "dashboard#dismiss_onboarding", as: "dismiss_onboarding"
    post  "/dismiss_announcement",          to: "dashboard#dismiss_announcement", as: "dismiss_announcement"

    # Profile management
    resources :profiles, only: [ :index, :new, :create ]

    # Productions
    get    "/productions",                  to: "productions#index",        as: "productions"
    get    "/productions/:id",              to: "productions#show",         as: "production"
    get    "/productions/:production_id/emails/:id", to: "productions#email", as: "production_email"
    delete "/productions/:id/leave",        to: "productions#leave",        as: "leave_production"

    get   "/shows",                         to: "shows#index",              as: "shows"
    get   "/shows/calendar",                to: "shows#calendar",           as: "shows_calendar"
    get   "/shows/:id",                     to: "shows#show",               as: "show"
    post  "/shows/:show_id/reclaim_vacancy/:vacancy_id", to: "shows#reclaim_vacancy", as: "reclaim_vacancy"
    get   "/availability",                  to: "availability#index",       as: "availability"
    get   "/availability/calendar",         to: "availability#calendar",    as: "availability_calendar"
    patch "/availability/:show_id",         to: "availability#update",      as: "update_availability"
    patch "/audition_availability/:session_id", to: "availability#update_audition_session", as: "update_audition_availability"
    get   "/auditions",                     to: "auditions#index",          as: "auditions"
    get   "/signups",                       to: "sign_ups#index",           as: "sign_ups"
    get   "/questionnaires",                to: "questionnaires#index",     as: "questionnaires"

    scope "/auditions/:token" do
      get "/", to: redirect { |params, _req| "/a/#{params[:token]}" }
      get "/form", to: "submit_audition_request#form", as: "submit_audition_request_form"
      post "/form", to: "submit_audition_request#submitform", as: "submit_submit_audition_request_form"
      get "/success", to: "submit_audition_request#success", as: "submit_audition_request_success"
      get "/inactive", to: "submit_audition_request#inactive", as: "submit_audition_request_inactive"
    end

    scope "/questionnaires/:token" do
      get "/form", to: "questionnaires#form", as: "questionnaire_form"
      post "/form", to: "questionnaires#submitform", as: "submit_questionnaire_form"
      get "/success", to: "questionnaires#success", as: "questionnaire_success"
      get "/inactive", to: "questionnaires#inactive", as: "questionnaire_inactive"
    end

    # Sign-up forms (public-facing)
    scope "/signups/:code" do
      get "/", to: "sign_ups#entry", as: "sign_up_entry"
      get "/form", to: "sign_ups#form", as: "sign_up_form"
      post "/form", to: "sign_ups#submit_form", as: "submit_sign_up_form"
      get "/success", to: "sign_ups#success", as: "sign_up_success"
      post "/change-slot", to: "sign_ups#change_slot", as: "change_sign_up_slot"
      post "/cancel", to: "sign_ups#cancel_registration", as: "cancel_sign_up_registration"
      get "/inactive", to: "sign_ups#inactive", as: "sign_up_inactive"
      # Slot locking (60-second hold while user completes registration)
      post "/lock/:slot_id", to: "sign_ups#lock_slot", as: "lock_sign_up_slot"
      delete "/lock/:slot_id", to: "sign_ups#unlock_slot", as: "unlock_sign_up_slot"
      post "/unlock/:slot_id", to: "sign_ups#unlock_slot", as: "beacon_unlock_sign_up_slot" # For sendBeacon on page unload
      get "/locks", to: "sign_ups#slot_locks", as: "sign_up_slot_locks"
    end

    # Payments (for talent to manage Venmo/Zelle settings and view history)
    get    "/payments",                          to: "payments#index",                     as: "payments"
    get    "/payments/setup",                    to: "payments#setup",                     as: "payments_setup"
    patch  "/payments/venmo",                    to: "payments#update_venmo",              as: "payments_update_venmo"
    delete "/payments/venmo",                    to: "payments#remove_venmo",              as: "payments_remove_venmo"
    patch  "/payments/zelle",                    to: "payments#update_zelle",              as: "payments_update_zelle"
    delete "/payments/zelle",                    to: "payments#remove_zelle",              as: "payments_remove_zelle"
    patch  "/payments/preferred",                to: "payments#update_preferred",          as: "payments_update_preferred"

    # Messages (inbox for talent)
    get   "/messages",                          to: "messages#index",                     as: "messages"
    post  "/messages",                          to: "messages#create",                    as: "create_message"
    get   "/messages/reply_form",               to: "messages#reply_form",                as: "messages_reply_form"
    get   "/messages/posts",                    to: "messages#posts",                     as: "messages_posts"
    get   "/messages/emails",                   to: "messages#emails",                    as: "messages_emails"
    post  "/messages/send",                     to: "messages#send_message",              as: "send_message_messages"
    get   "/messages/:id",                      to: "messages#show",                      as: "email_log"

    # Shoutouts management
    get   "/shoutouts",                         to: "shoutouts#index",                    as: "shoutouts"
    post  "/shoutouts",                         to: "shoutouts#create",                   as: "create_shoutout"
    get   "/shoutouts/search",                  to: "shoutouts#search_people_and_groups",
                                                as: "search_shoutout_recipients"
    get   "/shoutouts/check_existing",          to: "shoutouts#check_existing_shoutout", as: "check_existing_shoutout"

    # Calendar sync management
    get   "/calendar-sync",                     to: "calendar_sync#index",                as: "calendar_sync"
    get   "/calendar-sync/connect/google",      to: "calendar_sync#connect_google",       as: "calendar_sync_connect_google"
    get   "/calendar-sync/callback",            to: "calendar_sync#oauth_callback",       as: "calendar_oauth_callback"
    post  "/calendar-sync/ical",                to: "calendar_sync#create_ical",          as: "calendar_sync_create_ical"
    patch "/calendar-sync/:id",                 to: "calendar_sync#update",               as: "calendar_sync_update"
    delete "/calendar-sync/:id",                to: "calendar_sync#disconnect",           as: "calendar_sync_disconnect"
    post "/calendar-sync/:id/sync",            to: "calendar_sync#sync_now",             as: "calendar_sync_sync_now"
  end

  # iCal feed (public, no authentication)
  get "/calendar/:token.ics", to: "calendar_feeds#show", as: "calendar_feed"

  # Management interface
  namespace :manage do
    get  "/",                              to: "manage#index"
    get  "/welcome",                       to: "manage#welcome",                    as: "welcome"
    post "/dismiss_production_welcome",    to: "manage#dismiss_production_welcome", as: "dismiss_production_welcome"

    # Productions > Wizard
    get    "/productions/new",                to: "production_wizard#name",          as: "productions_wizard"
    post   "/productions/wizard/name",        to: "production_wizard#save_name",     as: "productions_wizard_save_name"
    get    "/productions/wizard/logo",        to: "production_wizard#logo",          as: "productions_wizard_logo"
    post   "/productions/wizard/logo",        to: "production_wizard#save_logo",     as: "productions_wizard_save_logo"
    get    "/productions/wizard/casting",     to: "production_wizard#casting",       as: "productions_wizard_casting"
    post   "/productions/wizard/casting",     to: "production_wizard#save_casting",  as: "productions_wizard_save_casting"
    get    "/productions/wizard/roles",       to: "production_wizard#roles",         as: "productions_wizard_roles"
    post   "/productions/wizard/roles",       to: "production_wizard#save_roles",    as: "productions_wizard_save_roles"
    get    "/productions/wizard/shows",       to: "production_wizard#shows",         as: "productions_wizard_shows"
    post   "/productions/wizard/shows",       to: "production_wizard#save_shows",    as: "productions_wizard_save_shows"
    get    "/productions/wizard/schedule",    to: "production_wizard#schedule",      as: "productions_wizard_schedule"
    post   "/productions/wizard/schedule",    to: "production_wizard#save_schedule", as: "productions_wizard_save_schedule"
    get    "/productions/wizard/review",      to: "production_wizard#review",        as: "productions_wizard_review"
    post   "/productions/wizard/create",      to: "production_wizard#create_production", as: "productions_wizard_create"
    delete "/productions/wizard/cancel",      to: "production_wizard#cancel",        as: "productions_wizard_cancel"

    # Shows & Events - org-level (aggregates all productions)
    get  "/shows",              to: "org_shows#index", as: "shows"
    get  "/shows/calendar",     to: "org_shows#calendar", as: "shows_calendar"
    get  "/shows/new",          to: "show_wizard#select_production", as: "shows_new_wizard"
    post "/shows/new",          to: "show_wizard#save_production_selection", as: "shows_save_production_selection"

    # Shows > Wizard (production-level)
    get  "/shows/:production_id/wizard", to: "show_wizard#event_type", as: "shows_wizard"
    post "/shows/:production_id/wizard/event_type", to: "show_wizard#save_event_type", as: "shows_wizard_save_event_type"
    get  "/shows/:production_id/wizard/schedule", to: "show_wizard#schedule", as: "shows_wizard_schedule"
    post "/shows/:production_id/wizard/schedule", to: "show_wizard#save_schedule", as: "shows_wizard_save_schedule"
    get  "/shows/:production_id/wizard/location", to: "show_wizard#location", as: "shows_wizard_location"
    post "/shows/:production_id/wizard/location", to: "show_wizard#save_location", as: "shows_wizard_save_location"
    get  "/shows/:production_id/wizard/details", to: "show_wizard#details", as: "shows_wizard_details"
    post "/shows/:production_id/wizard/details", to: "show_wizard#save_details", as: "shows_wizard_save_details"
    get  "/shows/:production_id/wizard/review", to: "show_wizard#review", as: "shows_wizard_review"
    post "/shows/:production_id/wizard/create", to: "show_wizard#create_show", as: "shows_wizard_create"
    delete "/shows/:production_id/wizard/cancel", to: "show_wizard#cancel", as: "shows_wizard_cancel"

    # Shows - production-level (new URL pattern: /manage/shows/:production_id)
    get  "/shows/:production_id",          to: "shows#index", as: "production_shows"
    get  "/shows/:production_id/calendar", to: "shows#calendar", as: "production_shows_calendar"
    get  "/shows/:production_id/:id",      to: "shows#show", as: "show"
    get  "/shows/:production_id/:id/edit", to: "shows#edit", as: "edit_show"
    patch "/shows/:production_id/:id",     to: "shows#update", as: "update_show"
    delete "/shows/:production_id/:id",    to: "shows#destroy"
    get "/shows/:production_id/:id/cancel", to: "shows#cancel", as: "cancel_show_form"
    patch "/shows/:production_id/:id/cancel_show", to: "shows#cancel_show", as: "cancel_show"
    delete "/shows/:production_id/:id/delete_show", to: "shows#delete_show", as: "delete_show"
    patch "/shows/:production_id/:id/uncancel", to: "shows#uncancel", as: "uncancel_show"
    post "/shows/:production_id/:id/link_show", to: "shows#link_show", as: "link_show"
    delete "/shows/:production_id/:id/unlink_show", to: "shows#unlink_show", as: "unlink_show"
    delete "/shows/:production_id/:id/delete_linkage", to: "shows#delete_linkage", as: "delete_linkage_show"
    post "/shows/:production_id/:id/toggle_signup_based_casting", to: "shows#toggle_signup_based_casting", as: "toggle_signup_based_casting_show"
    post "/shows/:production_id/:id/toggle_attendance", to: "shows#toggle_attendance", as: "toggle_attendance_show"
    get  "/shows/:production_id/:id/attendance", to: "shows#attendance", as: "attendance_show"
    patch "/shows/:production_id/:id/update_attendance", to: "shows#update_attendance", as: "update_attendance_show"
    post "/shows/:production_id/:id/create_walkin", to: "shows#create_walkin", as: "create_walkin_show"
    patch "/shows/:production_id/:id/transfer", to: "shows#transfer", as: "transfer_show"

    # Shows > Show Roles (custom roles per show)
    get  "/shows/:production_id/:show_id/roles", to: "show_roles#index", as: "show_roles"
    post "/shows/:production_id/:show_id/roles", to: "show_roles#create", as: "create_show_role"
    patch "/shows/:production_id/:show_id/roles/:id", to: "show_roles#update", as: "update_show_role"
    delete "/shows/:production_id/:show_id/roles/:id", to: "show_roles#destroy", as: "destroy_show_role"
    post "/shows/:production_id/:show_id/roles/reorder", to: "show_roles#reorder", as: "reorder_show_roles"
    post "/shows/:production_id/:show_id/roles/copy_from_production", to: "show_roles#copy_from_production", as: "copy_from_production_show_roles"
    get  "/shows/:production_id/:show_id/roles/talent_pool_members", to: "show_roles#talent_pool_members", as: "talent_pool_members_show_roles"
    get  "/shows/:production_id/:show_id/roles/check_assignments", to: "show_roles#check_assignments", as: "check_assignments_show_roles"
    post "/shows/:production_id/:show_id/roles/clear_assignments", to: "show_roles#clear_assignments", as: "clear_assignments_show_roles"
    post "/shows/:production_id/:show_id/roles/toggle_custom_roles", to: "show_roles#toggle_custom_roles", as: "toggle_custom_roles_show_roles"
    get  "/shows/:production_id/:show_id/roles/migration_preview", to: "show_roles#migration_preview", as: "migration_preview_show_roles"
    post "/shows/:production_id/:show_id/roles/execute_migration", to: "show_roles#execute_migration", as: "execute_migration_show_roles"
    get  "/shows/:production_id/:show_id/roles/:id/slot_change_preview", to: "show_roles#slot_change_preview", as: "slot_change_preview_show_role"
    post "/shows/:production_id/:show_id/roles/:id/execute_slot_change", to: "show_roles#execute_slot_change", as: "execute_slot_change_show_role"

    # Visual Assets (production-level)
    get  "/shows/:production_id/visual_assets", to: "visual_assets#index", as: "production_visual_assets"
    get  "/shows/:production_id/visual_assets/new_poster", to: "visual_assets#new_poster", as: "new_poster_production_visual_asset"
    post "/shows/:production_id/visual_assets/create_poster", to: "visual_assets#create_poster", as: "create_poster_production_visual_asset"
    get  "/shows/:production_id/visual_assets/new_logo", to: "visual_assets#new_logo", as: "new_logo_production_visual_asset"
    post "/shows/:production_id/visual_assets/create_logo", to: "visual_assets#create_logo", as: "create_logo_production_visual_asset"
    get  "/shows/:production_id/visual_assets/:id/edit_poster", to: "visual_assets#edit_poster", as: "edit_poster_production_visual_asset"
    patch "/shows/:production_id/visual_assets/:id/update_poster", to: "visual_assets#update_poster", as: "update_poster_production_visual_asset"
    delete "/shows/:production_id/visual_assets/:id/destroy_poster", to: "visual_assets#destroy_poster", as: "destroy_poster_production_visual_asset"
    patch "/shows/:production_id/visual_assets/:id/set_primary_poster", to: "visual_assets#set_primary_poster", as: "set_primary_poster_production_visual_asset"
    get "/shows/:production_id/visual_assets/:id/edit_logo", to: "visual_assets#edit_logo", as: "edit_logo_production_visual_asset"
    patch "/shows/:production_id/visual_assets/:id/update_logo", to: "visual_assets#update_logo", as: "update_logo_production_visual_asset"

    # Sign-ups - org-level (aggregates all productions)
    get  "/signups",            to: "org_signups#index", as: "signups"
    get  "/signups/forms",      to: "org_sign_up_forms#index", as: "signups_all_forms"
    get  "/signups/auditions",  to: "org_auditions#index", as: "signups_all_auditions"

    # Sign-ups - org-level wizards (production selection first)
    get  "/signups/forms/new",       to: "sign_up_form_wizard#select_production", as: "signups_forms_new_wizard"
    post "/signups/forms/new",       to: "sign_up_form_wizard#save_production_selection", as: "signups_forms_save_production_selection"
    get  "/signups/auditions/new",   to: "audition_cycle_wizard#select_production", as: "signups_auditions_new_wizard"
    post "/signups/auditions/new",   to: "audition_cycle_wizard#save_production_selection", as: "signups_auditions_save_production_selection"

    # Sign-ups - production-level (new URL pattern: /manage/signups/:production_id)
    get  "/signups/:production_id", to: "signups#index", as: "signups_production"

    # Sign-ups > Forms - production-level (new URL pattern: /manage/signups/forms/:production_id)
    get  "/signups/forms/:production_id", to: "sign_up_forms#index", as: "signups_forms"
    get  "/signups/forms/:production_id/archived", to: "sign_up_forms#archived", as: "signups_forms_archived"
    get  "/signups/forms/:production_id/new", to: "sign_up_forms#new", as: "new_signups_form"
    post "/signups/forms/:production_id", to: "sign_up_forms#create", as: "create_signups_form"

    # Sign-ups > Forms > Wizard (must come before :id routes)
    get  "/signups/forms/:production_id/wizard", to: "sign_up_form_wizard#scope", as: "signups_forms_wizard"
    post "/signups/forms/:production_id/wizard/scope", to: "sign_up_form_wizard#save_scope", as: "signups_forms_wizard_save_scope"
    get  "/signups/forms/:production_id/wizard/events", to: "sign_up_form_wizard#events", as: "signups_forms_wizard_events"
    post "/signups/forms/:production_id/wizard/events", to: "sign_up_form_wizard#save_events", as: "signups_forms_wizard_save_events"
    get  "/signups/forms/:production_id/wizard/slots", to: "sign_up_form_wizard#slots", as: "signups_forms_wizard_slots"
    post "/signups/forms/:production_id/wizard/slots", to: "sign_up_form_wizard#save_slots", as: "signups_forms_wizard_save_slots"
    get  "/signups/forms/:production_id/wizard/rules", to: "sign_up_form_wizard#rules", as: "signups_forms_wizard_rules"
    post "/signups/forms/:production_id/wizard/rules", to: "sign_up_form_wizard#save_rules", as: "signups_forms_wizard_save_rules"
    get  "/signups/forms/:production_id/wizard/schedule", to: "sign_up_form_wizard#schedule", as: "signups_forms_wizard_schedule"
    post "/signups/forms/:production_id/wizard/schedule", to: "sign_up_form_wizard#save_schedule", as: "signups_forms_wizard_save_schedule"
    get  "/signups/forms/:production_id/wizard/notifications", to: "sign_up_form_wizard#notifications", as: "signups_forms_wizard_notifications"
    post "/signups/forms/:production_id/wizard/notifications", to: "sign_up_form_wizard#save_notifications", as: "signups_forms_wizard_save_notifications"
    get  "/signups/forms/:production_id/wizard/review", to: "sign_up_form_wizard#review", as: "signups_forms_wizard_review"
    post "/signups/forms/:production_id/wizard/create", to: "sign_up_form_wizard#create_form", as: "signups_forms_wizard_create"
    delete "/signups/forms/:production_id/wizard/cancel", to: "sign_up_form_wizard#cancel", as: "signups_forms_wizard_cancel"

    get  "/signups/forms/:production_id/:id", to: "sign_up_forms#show", as: "signups_form"
    get  "/signups/forms/:production_id/:id/edit", to: "sign_up_forms#edit", as: "edit_signups_form"
    patch "/signups/forms/:production_id/:id", to: "sign_up_forms#update", as: "update_signups_form"
    delete "/signups/forms/:production_id/:id", to: "sign_up_forms#destroy", as: "destroy_signups_form"
    get "/signups/forms/:production_id/:id/settings", to: "sign_up_forms#settings", as: "settings_signups_form"
    patch "/signups/forms/:production_id/:id/update_settings", to: "sign_up_forms#update_settings", as: "update_settings_signups_form"
    get  "/signups/forms/:production_id/:id/preview", to: "sign_up_forms#preview", as: "preview_signups_form"
    get  "/signups/forms/:production_id/:id/print_list", to: "sign_up_forms#print_list", as: "print_list_signups_form"
    get  "/signups/forms/:production_id/:id/assign", to: "sign_up_forms#assign", as: "assign_signups_form"
    patch "/signups/forms/:production_id/:id/toggle_active", to: "sign_up_forms#toggle_active", as: "toggle_active_signups_form"
    patch "/signups/forms/:production_id/:id/archive", to: "sign_up_forms#archive", as: "archive_signups_form"
    patch "/signups/forms/:production_id/:id/unarchive", to: "sign_up_forms#unarchive", as: "unarchive_signups_form"
    patch "/signups/forms/:production_id/:id/transfer", to: "sign_up_forms#transfer", as: "transfer_signups_form"
    get "/signups/forms/:production_id/:id/confirm_slot_changes", to: "sign_up_forms#confirm_slot_changes", as: "confirm_slot_changes_signups_form"
    patch "/signups/forms/:production_id/:id/apply_slot_changes", to: "sign_up_forms#apply_slot_changes", as: "apply_slot_changes_signups_form"
    get "/signups/forms/:production_id/:id/confirm_event_changes", to: "sign_up_forms#confirm_event_changes", as: "confirm_event_changes_signups_form"
    patch "/signups/forms/:production_id/:id/apply_event_changes", to: "sign_up_forms#apply_event_changes", as: "apply_event_changes_signups_form"
    post "/signups/forms/:production_id/:id/create_slot", to: "sign_up_forms#create_slot", as: "create_slot_signups_form"
    patch "/signups/forms/:production_id/:id/update_slot/:slot_id", to: "sign_up_forms#update_slot", as: "update_slot_signups_form"
    delete "/signups/forms/:production_id/:id/destroy_slot/:slot_id", to: "sign_up_forms#destroy_slot", as: "destroy_slot_signups_form"
    post "/signups/forms/:production_id/:id/reorder_slots", to: "sign_up_forms#reorder_slots", as: "reorder_slots_signups_form"
    post "/signups/forms/:production_id/:id/generate_slots", to: "sign_up_forms#generate_slots", as: "generate_slots_signups_form"
    patch "/signups/forms/:production_id/:id/toggle_slot_hold/:slot_id", to: "sign_up_forms#toggle_slot_hold", as: "toggle_slot_hold_signups_form"
    get  "/signups/forms/:production_id/:id/holdouts", to: "sign_up_forms#holdouts", as: "holdouts_signups_form"
    post "/signups/forms/:production_id/:id/create_holdout", to: "sign_up_forms#create_holdout", as: "create_holdout_signups_form"
    delete "/signups/forms/:production_id/:id/destroy_holdout/:holdout_id", to: "sign_up_forms#destroy_holdout", as: "destroy_holdout_signups_form"
    post "/signups/forms/:production_id/:id/create_question", to: "sign_up_forms#create_question", as: "create_question_signups_form"
    patch "/signups/forms/:production_id/:id/update_question/:question_id", to: "sign_up_forms#update_question", as: "update_question_signups_form"
    delete "/signups/forms/:production_id/:id/destroy_question/:question_id", to: "sign_up_forms#destroy_question", as: "destroy_question_signups_form"
    post "/signups/forms/:production_id/:id/reorder_questions", to: "sign_up_forms#reorder_questions", as: "reorder_questions_signups_form"
    post "/signups/forms/:production_id/:id/register", to: "sign_up_forms#register", as: "register_signups_form"
    post "/signups/forms/:production_id/:id/register_to_queue", to: "sign_up_forms#register_to_queue", as: "register_to_queue_signups_form"
    delete "/signups/forms/:production_id/:id/cancel_registration/:registration_id", to: "sign_up_forms#cancel_registration", as: "cancel_registration_signups_form"
    patch "/signups/forms/:production_id/:id/move_registration/:registration_id", to: "sign_up_forms#move_registration", as: "move_registration_signups_form"
    patch "/signups/forms/:production_id/:id/assign_registration/:registration_id", to: "sign_up_forms#assign_registration", as: "assign_registration_signups_form"
    patch "/signups/forms/:production_id/:id/unassign_registration/:registration_id", to: "sign_up_forms#unassign_registration", as: "unassign_registration_signups_form"
    post "/signups/forms/:production_id/:id/auto_assign_queue", to: "sign_up_forms#auto_assign_queue", as: "auto_assign_queue_signups_form"
    post "/signups/forms/:production_id/:id/auto_assign_one/:registration_id", to: "sign_up_forms#auto_assign_one", as: "auto_assign_one_signups_form"

    # Sign-ups > Auditions - production-level (new URL pattern: /manage/signups/auditions/:production_id)
    get  "/signups/auditions/:production_id", to: "auditions#index", as: "signups_auditions"
    get  "/signups/auditions/:production_id/archive", to: "auditions#archive", as: "signups_auditions_archive"

    # Sign-ups > Auditions > Wizard (must come before :id routes)
    get  "/signups/auditions/:production_id/wizard", to: "audition_cycle_wizard#format", as: "signups_auditions_wizard"
    post "/signups/auditions/:production_id/wizard/format", to: "audition_cycle_wizard#save_format", as: "signups_auditions_wizard_save_format"
    get  "/signups/auditions/:production_id/wizard/schedule", to: "audition_cycle_wizard#schedule", as: "signups_auditions_wizard_schedule"
    post "/signups/auditions/:production_id/wizard/schedule", to: "audition_cycle_wizard#save_schedule", as: "signups_auditions_wizard_save_schedule"
    get  "/signups/auditions/:production_id/wizard/sessions", to: "audition_cycle_wizard#sessions", as: "signups_auditions_wizard_sessions"
    post "/signups/auditions/:production_id/wizard/sessions", to: "audition_cycle_wizard#save_sessions", as: "signups_auditions_wizard_save_sessions"
    post "/signups/auditions/:production_id/wizard/sessions/generate", to: "audition_cycle_wizard#generate_sessions", as: "signups_auditions_wizard_generate_sessions"
    post "/signups/auditions/:production_id/wizard/sessions/add", to: "audition_cycle_wizard#add_session", as: "signups_auditions_wizard_add_session"
    patch "/signups/auditions/:production_id/wizard/sessions/:session_index", to: "audition_cycle_wizard#update_session", as: "signups_auditions_wizard_update_session"
    delete "/signups/auditions/:production_id/wizard/sessions/:session_index", to: "audition_cycle_wizard#delete_session", as: "signups_auditions_wizard_delete_session"
    get  "/signups/auditions/:production_id/wizard/availability", to: "audition_cycle_wizard#availability", as: "signups_auditions_wizard_availability"
    post "/signups/auditions/:production_id/wizard/availability", to: "audition_cycle_wizard#save_availability", as: "signups_auditions_wizard_save_availability"
    get  "/signups/auditions/:production_id/wizard/reviewers", to: "audition_cycle_wizard#reviewers", as: "signups_auditions_wizard_reviewers"
    post "/signups/auditions/:production_id/wizard/reviewers", to: "audition_cycle_wizard#save_reviewers", as: "signups_auditions_wizard_save_reviewers"
    get  "/signups/auditions/:production_id/wizard/voting", to: "audition_cycle_wizard#voting", as: "signups_auditions_wizard_voting"
    post "/signups/auditions/:production_id/wizard/voting", to: "audition_cycle_wizard#save_voting", as: "signups_auditions_wizard_save_voting"
    get  "/signups/auditions/:production_id/wizard/notifications", to: "audition_cycle_wizard#notifications", as: "signups_auditions_wizard_notifications"
    post "/signups/auditions/:production_id/wizard/notifications", to: "audition_cycle_wizard#save_notifications", as: "signups_auditions_wizard_save_notifications"
    get  "/signups/auditions/:production_id/wizard/review", to: "audition_cycle_wizard#review", as: "signups_auditions_wizard_review"
    post "/signups/auditions/:production_id/wizard/create", to: "audition_cycle_wizard#create_cycle", as: "signups_auditions_wizard_create"
    delete "/signups/auditions/:production_id/wizard/cancel", to: "audition_cycle_wizard#cancel", as: "signups_auditions_wizard_cancel"

    # Sign-ups > Auditions > Cycles (new URL pattern: /manage/signups/auditions/:production_id/:id)
    get  "/signups/auditions/:production_id/:id", to: "audition_cycles#show", as: "signups_auditions_cycle"
    get  "/signups/auditions/:production_id/:id/edit", to: "audition_cycles#edit", as: "edit_signups_auditions_cycle"
    patch "/signups/auditions/:production_id/:id", to: "audition_cycles#update", as: "update_signups_auditions_cycle"
    delete "/signups/auditions/:production_id/:id", to: "audition_cycles#destroy", as: "destroy_signups_auditions_cycle"
    get  "/signups/auditions/:production_id/:id/form", to: "audition_cycles#form", as: "form_signups_auditions_cycle"
    get  "/signups/auditions/:production_id/:id/preview", to: "audition_cycles#preview", as: "preview_signups_auditions_cycle"
    post "/signups/auditions/:production_id/:id/create_question", to: "audition_cycles#create_question", as: "create_question_signups_auditions_cycle"
    patch "/signups/auditions/:production_id/:id/update_question/:question_id", to: "audition_cycles#update_question", as: "update_question_signups_auditions_cycle"
    delete "/signups/auditions/:production_id/:id/destroy_question/:question_id", to: "audition_cycles#destroy_question", as: "destroy_question_signups_auditions_cycle"
    post "/signups/auditions/:production_id/:id/reorder_questions", to: "audition_cycles#reorder_questions", as: "reorder_questions_signups_auditions_cycle"
    patch "/signups/auditions/:production_id/:id/archive", to: "audition_cycles#archive", as: "archive_signups_auditions_cycle"
    get "/signups/auditions/:production_id/:id/delete_confirm", to: "audition_cycles#delete_confirm", as: "delete_confirm_signups_auditions_cycle"
    patch "/signups/auditions/:production_id/:id/toggle_voting", to: "audition_cycles#toggle_voting", as: "toggle_voting_signups_auditions_cycle"
    get "/signups/auditions/:production_id/:id/prepare", to: "auditions#prepare", as: "prepare_signups_auditions_cycle"
    patch "/signups/auditions/:production_id/:id/update_reviewers", to: "auditions#update_reviewers", as: "update_reviewers_signups_auditions_cycle"
    get  "/signups/auditions/:production_id/:id/publicize", to: "auditions#publicize", as: "publicize_signups_auditions_cycle"
    get  "/signups/auditions/:production_id/:id/review", to: "auditions#review", as: "review_signups_auditions_cycle"
    patch "/signups/auditions/:production_id/:id/finalize_invitations", to: "auditions#finalize_invitations", as: "finalize_invitations_signups_auditions_cycle"
    get  "/signups/auditions/:production_id/:id/run", to: "auditions#run", as: "run_signups_auditions_cycle"
    get  "/signups/auditions/:production_id/:id/casting", to: "auditions#casting", as: "casting_signups_auditions_cycle"
    get  "/signups/auditions/:production_id/:id/casting/select", to: "auditions#casting_select", as: "casting_select_signups_auditions_cycle"
    post "/signups/auditions/:production_id/:id/add_to_cast_assignment", to: "auditions#add_to_cast_assignment", as: "add_to_cast_assignment_signups_auditions_cycle"
    post "/signups/auditions/:production_id/:id/remove_from_cast_assignment", to: "auditions#remove_from_cast_assignment", as: "remove_from_cast_assignment_signups_auditions_cycle"
    post "/signups/auditions/:production_id/:id/finalize_and_notify", to: "auditions#finalize_and_notify", as: "finalize_and_notify_signups_auditions_cycle"
    post "/signups/auditions/:production_id/:id/finalize_and_notify_invitations", to: "auditions#finalize_and_notify_invitations", as: "finalize_and_notify_invitations_signups_auditions_cycle"
    get  "/signups/auditions/:production_id/:id/schedule_auditions", to: "auditions#schedule_auditions", as: "schedule_auditions_signups_auditions_cycle"
    get  "/signups/auditions/:production_id/:id/communicate", to: "auditions#communicate", as: "communicate_signups_auditions_cycle"

    # Sign-ups > Auditions > Requests
    get  "/signups/auditions/:production_id/:cycle_id/requests", to: "audition_requests#index", as: "signups_auditions_cycle_requests"
    get  "/signups/auditions/:production_id/:cycle_id/requests/new", to: "audition_requests#new", as: "new_signups_auditions_cycle_request"
    post "/signups/auditions/:production_id/:cycle_id/requests", to: "audition_requests#create", as: "create_signups_auditions_cycle_request"
    get  "/signups/auditions/:production_id/:cycle_id/requests/:id", to: "audition_requests#show", as: "signups_auditions_cycle_request"
    get  "/signups/auditions/:production_id/:cycle_id/requests/:id/edit", to: "audition_requests#edit", as: "edit_signups_auditions_cycle_request"
    patch "/signups/auditions/:production_id/:cycle_id/requests/:id", to: "audition_requests#update", as: "update_signups_auditions_cycle_request"
    delete "/signups/auditions/:production_id/:cycle_id/requests/:id", to: "audition_requests#destroy", as: "destroy_signups_auditions_cycle_request"
    get  "/signups/auditions/:production_id/:cycle_id/requests/:id/edit_answers", to: "audition_requests#edit_answers", as: "edit_answers_signups_auditions_cycle_request"
    get  "/signups/auditions/:production_id/:cycle_id/requests/:id/edit_video", to: "audition_requests#edit_video", as: "edit_video_signups_auditions_cycle_request"
    patch "/signups/auditions/:production_id/:cycle_id/requests/:id/update_audition_session_availability", to: "audition_requests#update_audition_session_availability", as: "update_session_availability_signups_auditions_cycle_request"
    post "/signups/auditions/:production_id/:cycle_id/requests/:id/cast_vote", to: "audition_requests#cast_vote", as: "cast_vote_signups_auditions_cycle_request"
    get  "/signups/auditions/:production_id/:cycle_id/requests/:id/votes", to: "audition_requests#votes", as: "votes_signups_auditions_cycle_request"

    # Sign-ups > Auditions > Sessions
    get  "/signups/auditions/:production_id/:cycle_id/sessions", to: "audition_sessions#index", as: "signups_auditions_cycle_sessions"
    get  "/signups/auditions/:production_id/:cycle_id/sessions/summary", to: "audition_sessions#summary", as: "signups_auditions_cycle_sessions_summary"
    get  "/signups/auditions/:production_id/:cycle_id/sessions/new", to: "audition_sessions#new", as: "new_signups_auditions_cycle_session"
    post "/signups/auditions/:production_id/:cycle_id/sessions", to: "audition_sessions#create", as: "create_signups_auditions_cycle_session"
    get  "/signups/auditions/:production_id/:cycle_id/sessions/:id", to: "audition_sessions#show", as: "signups_auditions_cycle_session"
    get  "/signups/auditions/:production_id/:cycle_id/sessions/:id/edit", to: "audition_sessions#edit", as: "edit_signups_auditions_cycle_session"
    patch "/signups/auditions/:production_id/:cycle_id/sessions/:id", to: "audition_sessions#update", as: "update_signups_auditions_cycle_session"
    delete "/signups/auditions/:production_id/:cycle_id/sessions/:id", to: "audition_sessions#destroy", as: "destroy_signups_auditions_cycle_session"

    # Sign-ups > Auditions > Sessions > Auditions (individual audition slots)
    get  "/signups/auditions/:production_id/:cycle_id/sessions/:session_id/auditions/:id", to: "auditions#show", as: "signups_auditions_cycle_session_audition"
    post "/signups/auditions/:production_id/:cycle_id/sessions/:session_id/auditions/:id/cast_vote", to: "auditions#cast_audition_vote", as: "cast_vote_signups_auditions_cycle_session_audition"

    # Casting - org-level (aggregates all productions)
    get  "/casting",            to: "org_casting#index", as: "casting"
    get  "/casting/roles",      to: "org_roles#index", as: "casting_roles"
    get  "/casting/talent-pools", to: "org_talent_pools#index", as: "casting_talent_pools"
    get  "/casting/talent-pools/switch-to-single", to: "org_talent_pools#switch_to_single_confirm", as: "casting_talent_pools_switch_to_single_confirm"
    post "/casting/talent-pools/switch-to-single", to: "org_talent_pools#switch_to_single", as: "casting_talent_pools_switch_to_single"
    get  "/casting/talent-pools/switch-to-per-production", to: "org_talent_pools#switch_to_per_production_confirm", as: "casting_talent_pools_switch_to_per_production_confirm"
    post "/casting/talent-pools/switch-to-per-production", to: "org_talent_pools#switch_to_per_production", as: "casting_talent_pools_switch_to_per_production"

    # Casting Tables (org-level)
    get  "/casting/tables",              to: "casting_tables#index", as: "casting_tables"
    get  "/casting/tables/new",          to: "casting_table_wizard#productions", as: "casting_tables_new"
    post "/casting/tables/new",          to: "casting_table_wizard#save_productions", as: "casting_tables_save_productions"
    get  "/casting/tables/new/events",   to: "casting_table_wizard#events", as: "casting_tables_events"
    post "/casting/tables/new/events",   to: "casting_table_wizard#save_events", as: "casting_tables_save_events"
    get  "/casting/tables/new/members",  to: "casting_table_wizard#members", as: "casting_tables_members"
    post "/casting/tables/new/members",  to: "casting_table_wizard#save_members", as: "casting_tables_save_members"
    get  "/casting/tables/new/review",   to: "casting_table_wizard#review", as: "casting_tables_review"
    post "/casting/tables/new/create",   to: "casting_table_wizard#create_table", as: "casting_tables_create"
    delete "/casting/tables/new/cancel", to: "casting_table_wizard#cancel", as: "casting_tables_cancel"

    # Casting Table (individual)
    get   "/casting/tables/:id",           to: "casting_tables#show", as: "casting_table"
    get   "/casting/tables/:id/edit",      to: "casting_tables#edit_events", as: "edit_casting_table"
    patch "/casting/tables/:id",           to: "casting_tables#update", as: "update_casting_table"
    post  "/casting/tables/:id/assign",    to: "casting_tables#assign", as: "casting_table_assign"
    delete "/casting/tables/:id/unassign", to: "casting_tables#unassign", as: "casting_table_unassign"
    get   "/casting/tables/:id/summary",   to: "casting_tables#summary", as: "casting_table_summary"
    post  "/casting/tables/:id/finalize",  to: "casting_tables#finalize", as: "casting_table_finalize"

    # Casting Table - Edit Members (separate tab)
    get   "/casting/tables/:id/edit/members", to: "casting_tables#edit_members", as: "casting_table_edit_members"
    post  "/casting/tables/:id/add_event",    to: "casting_tables#add_event", as: "casting_table_add_event"
    delete "/casting/tables/:id/remove_event/:show_id", to: "casting_tables#remove_event", as: "casting_table_remove_event"
    post "/casting/tables/:id/add_member",   to: "casting_tables#add_member", as: "casting_table_add_member"
    delete "/casting/tables/:id/remove_member/:memberable_type/:memberable_id", to: "casting_tables#remove_member", as: "casting_table_remove_member"

    # Organization-wide Availability (must be before :production_id routes)
    get  "/casting/availability", to: "org_availability#index", as: "org_availability"
    get  "/casting/availability/person_modal/:id", to: "org_availability#person_modal", as: "org_availability_person_modal"
    get  "/casting/availability/show_modal/:id", to: "org_availability#show_modal", as: "org_availability_show_modal"
    post "/casting/availability/cast_person", to: "org_availability#cast_person", as: "org_availability_cast_person"
    post "/casting/availability/sign_up_person", to: "org_availability#sign_up_person", as: "org_availability_sign_up_person"
    post "/casting/availability/register_person", to: "org_availability#register_person", as: "org_availability_register_person"
    post "/casting/availability/pre_register", to: "org_availability#pre_register", as: "org_availability_pre_register"
    post "/casting/availability/pre_register_all", to: "org_availability#pre_register_all", as: "org_availability_pre_register_all"
    post "/casting/availability/set_availability", to: "org_availability#set_availability", as: "org_availability_set_availability"

    # Casting - production-level (new URL pattern: /manage/casting/:production_id)
    get  "/casting/:production_id", to: "casting#index", as: "casting_production"
    get  "/casting/:production_id/settings", to: "casting_settings#show", as: "casting_settings"
    patch "/casting/:production_id/settings", to: "casting_settings#update", as: "update_casting_settings"
    get  "/casting/:production_id/settings/setup", to: "casting_settings#setup", as: "setup_casting_settings"
    post "/casting/:production_id/settings/complete_setup", to: "casting_settings#complete_setup", as: "complete_setup_casting_settings"
    get  "/casting/:production_id/search_people", to: "casting#search_people", as: "casting_search_people"

    # Casting > Availability (new URL pattern: /manage/casting/:production_id/availability)
    get  "/casting/:production_id/availability", to: "casting_availability#index", as: "casting_availability"
    get  "/casting/:production_id/availability/:id/show_modal", to: "casting_availability#show_modal", as: "show_modal_casting_availability"
    patch "/casting/:production_id/availability/:id/update_show_availability", to: "casting_availability#update_show_availability", as: "update_show_availability_casting_availability"

    # Casting > Roles
    post "/casting/:production_id/roles", to: "roles#create", as: "create_casting_role"
    patch "/casting/:production_id/roles/:id", to: "roles#update", as: "update_casting_role"
    delete "/casting/:production_id/roles/:id", to: "roles#destroy", as: "destroy_casting_role"
    post "/casting/:production_id/roles/reorder", to: "roles#reorder", as: "reorder_casting_roles"

    # Casting > Talent Pools
    get  "/casting/:production_id/talent-pools", to: "talent_pools#show", as: "casting_talent_pool"
    get  "/casting/:production_id/talent-pools/search_people", to: "talent_pools#search_people", as: "casting_talent_pool_search_people"
    post "/casting/:production_id/talent-pools/add_person", to: "talent_pools#add_person", as: "casting_talent_pool_add_person"
    post "/casting/:production_id/talent-pools/add_global_person", to: "talent_pools#add_global_person", as: "casting_talent_pool_add_global_person"
    post "/casting/:production_id/talent-pools/invite_to_pool", to: "talent_pools#invite_to_pool", as: "casting_talent_pool_invite_to_pool"
    post "/casting/:production_id/talent-pools/revoke_invitation", to: "talent_pools#revoke_invitation", as: "casting_talent_pool_revoke_invitation"
    get  "/casting/:production_id/talent-pools/confirm-remove-person/:person_id", to: "talent_pools#confirm_remove_person", as: "casting_talent_pool_confirm_remove_person"
    post "/casting/:production_id/talent-pools/remove_person", to: "talent_pools#remove_person", as: "casting_talent_pool_remove_person"
    post "/casting/:production_id/talent-pools/add_group", to: "talent_pools#add_group", as: "casting_talent_pool_add_group"
    get  "/casting/:production_id/talent-pools/confirm-remove-group/:group_id", to: "talent_pools#confirm_remove_group", as: "casting_talent_pool_confirm_remove_group"
    post "/casting/:production_id/talent-pools/remove_group", to: "talent_pools#remove_group", as: "casting_talent_pool_remove_group"
    get  "/casting/:production_id/talent-pools/upcoming_assignments/:id", to: "talent_pools#upcoming_assignments", as: "casting_talent_pool_upcoming_assignments"
    patch "/casting/:production_id/talent-pools/update_shares", to: "talent_pools#update_shares", as: "casting_talent_pool_update_shares"
    get  "/casting/:production_id/talent-pools/leave_shared_pool_confirm", to: "talent_pools#leave_shared_pool_confirm", as: "casting_talent_pool_leave_shared_pool_confirm"
    post "/casting/:production_id/talent-pools/leave_shared_pool", to: "talent_pools#leave_shared_pool", as: "casting_talent_pool_leave_shared_pool"

    # Casting > Shows (new URL pattern: /manage/casting/:production_id/:show_id)
    get  "/casting/:production_id/:show_id/cast", to: "casting#show_cast", as: "casting_show_cast"
    get  "/casting/:production_id/:show_id/contact", to: "casting#contact_cast", as: "casting_show_contact"
    post "/casting/:production_id/:show_id/contact", to: "casting#send_cast_email", as: "casting_show_send_email"
    post "/casting/:production_id/:show_id/assign_person_to_role", to: "casting#assign_person_to_role", as: "casting_show_assign_person"
    post "/casting/:production_id/:show_id/assign_guest_to_role", to: "casting#assign_guest_to_role", as: "casting_show_assign_guest"
    post "/casting/:production_id/:show_id/remove_person_from_role", to: "casting#remove_person_from_role", as: "casting_show_remove_person"
    post "/casting/:production_id/:show_id/replace_assignment", to: "casting#replace_assignment", as: "casting_show_replace_assignment"
    post "/casting/:production_id/:show_id/create_vacancy", to: "casting#create_vacancy", as: "casting_show_create_vacancy"
    post "/casting/:production_id/:show_id/finalize", to: "casting#finalize_casting", as: "casting_show_finalize"
    patch "/casting/:production_id/:show_id/reopen", to: "casting#reopen_casting", as: "casting_show_reopen"
    post "/casting/:production_id/:show_id/copy_cast_to_linked", to: "casting#copy_cast_to_linked", as: "casting_show_copy_to_linked"

    # Casting > Vacancies
    get  "/casting/:production_id/vacancies/:id", to: "vacancies#show", as: "casting_vacancy"
    post "/casting/:production_id/vacancies/:id/send_invitations", to: "vacancies#send_invitations", as: "send_invitations_casting_vacancy"
    post "/casting/:production_id/vacancies/:id/cancel", to: "vacancies#cancel", as: "cancel_casting_vacancy"
    post "/casting/:production_id/vacancies/:id/fill", to: "vacancies#fill", as: "fill_casting_vacancy"
    post "/casting/:production_id/vacancies/:id/invitations/:invitation_id/resend", to: "vacancy_invitations#resend", as: "resend_casting_vacancy_invitation"

    # Communications - org-level (aggregates all productions)
    get  "/communications",     to: "org_communications#index", as: "communications"
    post "/communications/send_message", to: "org_communications#send_message", as: "org_communications_send_message"
    get  "/communications/talent_pool_members/:production_id", to: "org_communications#talent_pool_members", as: "org_communications_talent_pool_members"
    get  "/communications/questionnaires", to: "org_questionnaires#index", as: "communications_all_questionnaires"
    get  "/communications/questionnaires/new", to: "questionnaires#select_production", as: "communications_questionnaires_new_wizard"
    post "/communications/questionnaires/new", to: "questionnaires#save_production_selection", as: "communications_questionnaires_save_production_selection"

    # Communications - production-level (new URL pattern: /manage/communications/:production_id)
    get  "/communications/:production_id", to: "communications#index", as: "communications_production"
    get  "/communications/:production_id/:id", to: "communications#show", as: "communication"
    post "/communications/:production_id/send_message", to: "communications#send_message", as: "communications_send_message"

    # Questionnaires (under communications)
    get  "/communications/:production_id/questionnaires", to: "questionnaires#index", as: "communications_questionnaires"
    get  "/communications/:production_id/questionnaires/new", to: "questionnaires#new", as: "new_communications_questionnaire"
    post "/communications/:production_id/questionnaires", to: "questionnaires#create", as: "create_communications_questionnaire"
    get  "/communications/:production_id/questionnaires/:id", to: "questionnaires#show", as: "communications_questionnaire"
    get  "/communications/:production_id/questionnaires/:id/edit", to: "questionnaires#edit", as: "edit_communications_questionnaire"
    patch "/communications/:production_id/questionnaires/:id", to: "questionnaires#update", as: "update_communications_questionnaire"
    delete "/communications/:production_id/questionnaires/:id", to: "questionnaires#destroy", as: "destroy_communications_questionnaire"
    get  "/communications/:production_id/questionnaires/:id/form", to: "questionnaires#form", as: "form_communications_questionnaire"
    get  "/communications/:production_id/questionnaires/:id/preview", to: "questionnaires#preview", as: "preview_communications_questionnaire"
    post "/communications/:production_id/questionnaires/:id/create_question", to: "questionnaires#create_question", as: "create_question_communications_questionnaire"
    patch "/communications/:production_id/questionnaires/:id/update_question/:question_id", to: "questionnaires#update_question", as: "update_question_communications_questionnaire"
    delete "/communications/:production_id/questionnaires/:id/destroy_question/:question_id", to: "questionnaires#destroy_question", as: "destroy_question_communications_questionnaire"
    post "/communications/:production_id/questionnaires/:id/reorder_questions", to: "questionnaires#reorder_questions", as: "reorder_questions_communications_questionnaire"
    post "/communications/:production_id/questionnaires/:id/invite_people", to: "questionnaires#invite_people", as: "invite_people_communications_questionnaire"
    patch "/communications/:production_id/questionnaires/:id/archive", to: "questionnaires#archive", as: "archive_communications_questionnaire"
    patch "/communications/:production_id/questionnaires/:id/unarchive", to: "questionnaires#unarchive", as: "unarchive_communications_questionnaire"
    get  "/communications/:production_id/questionnaires/:id/responses", to: "questionnaires#responses", as: "responses_communications_questionnaire"
    get  "/communications/:production_id/questionnaires/:id/responses/:response_id", to: "questionnaires#show_response", as: "response_communications_questionnaire"
    get  "/communications/:production_id/questionnaires/:id/request_invitations", to: "questionnaires#request_invitations", as: "request_invitations_communications_questionnaire"

    # Email Groups (under communications, used for casting email notifications)
    post "/communications/:production_id/email_groups", to: "email_groups#create", as: "create_communications_email_group"
    patch "/communications/:production_id/email_groups/:id", to: "email_groups#update", as: "update_communications_email_group"
    delete "/communications/:production_id/email_groups/:id", to: "email_groups#destroy", as: "destroy_communications_email_group"

    # Audition Email Assignments (under communications)
    post "/communications/:production_id/audition_email_assignments", to: "audition_email_assignments#create", as: "create_communications_audition_email_assignment"
    patch "/communications/:production_id/audition_email_assignments/:id", to: "audition_email_assignments#update", as: "update_communications_audition_email_assignment"
    delete "/communications/:production_id/audition_email_assignments/:id", to: "audition_email_assignments#destroy", as: "destroy_communications_audition_email_assignment"

    # Directory - unified people and groups listing
    get  "/directory",          to: "directory#index", as: "directory"
    post "/directory/contact",  to: "directory#contact_directory", as: "contact_directory"
    patch "/directory/group/:id/update_availability", to: "directory#update_group_availability",
                                                      as: "update_group_availability"

    # Directory - people (new URL pattern: /manage/directory/people/:id)
    get  "/directory/people/new", to: "people#new", as: "new_directory_person"
    post "/directory/people", to: "people#create", as: "create_directory_person"
    get  "/directory/people/search", to: "people#search", as: "search_directory_people"
    post "/directory/people/batch_invite", to: "people#batch_invite", as: "batch_invite_directory_people"
    get  "/directory/people/check_email", to: "people#check_email", as: "check_email_directory_people"
    get  "/directory/people/:id", to: "people#show", as: "directory_person"
    get  "/directory/people/:id/edit", to: "people#edit", as: "edit_directory_person"
    patch "/directory/people/:id", to: "people#update", as: "update_directory_person"
    post "/directory/people/:id/add_to_cast", to: "people#add_to_cast", as: "add_to_cast_directory_person"
    post "/directory/people/:id/remove_from_cast", to: "people#remove_from_cast", as: "remove_from_cast_directory_person"
    post "/directory/people/:id/remove_from_organization", to: "people#remove_from_organization", as: "remove_from_organization_directory_person"
    get  "/directory/people/:id/contact", to: "people#contact", as: "contact_directory_person"
    post "/directory/people/:id/send_contact_email", to: "people#send_contact_email", as: "send_contact_email_directory_person"
    patch "/directory/people/:id/update_availability", to: "people#update_availability", as: "update_availability_directory_person"
    get  "/directory/people/:id/availability_modal", to: "people#availability_modal", as: "availability_modal_directory_person"

    # Directory - groups (new URL pattern: /manage/directory/groups/:id)
    get  "/directory/groups/:id", to: "groups#show", as: "directory_group"
    patch "/directory/groups/:id", to: "groups#update", as: "update_directory_group"
    delete "/directory/groups/:id", to: "groups#destroy", as: "destroy_directory_group"
    post "/directory/groups/:id/add_to_cast", to: "groups#add_to_cast", as: "add_to_cast_directory_group"
    post "/directory/groups/:id/remove_from_cast", to: "groups#remove_from_cast", as: "remove_from_cast_directory_group"
    post "/directory/groups/:id/remove_from_organization", to: "groups#remove_from_organization", as: "remove_from_organization_directory_group"
    patch "/directory/groups/:id/update_availability", to: "groups#update_availability", as: "update_availability_directory_group"
    get "/directory/groups/:id/availability_modal", to: "groups#availability_modal", as: "availability_modal_directory_group"

    resources :organizations do
      collection do
        get :setup_guide
      end
      member do
        get :confirm_delete
        post :transfer_ownership
        delete :remove_logo
        patch :toggle_production_forum
      end
    end

    resources :team, only: [ :index ] do
      collection do
        post :invite
        post :check_profiles
        delete :revoke_invite
        delete :remove_member
      end
      member do
        get :permissions
        patch :update_production_permission
        patch :update_production_notifications
        patch :update_global_role
        patch :update_global_notifications
      end
    end

    resources :team_invitations do
      collection do
        get "accept/:token", to: "team_invitations#accept", as: :accept
        post "accept/:token", to: "team_invitations#do_accept", as: :do_accept
      end
    end

    # Person invitations - for inviting cast members to join a production company
    get  "person_invitations/accept/:token",  to: "person_invitations#accept",    as: "accept_person_invitations"
    post "person_invitations/accept/:token",  to: "person_invitations#do_accept", as: "do_accept_person_invitations"
    post "person_invitations/decline/:token", to: "person_invitations#decline",   as: "decline_person_invitations"

    resources :people, except: [ :destroy ] do
      collection do
        get :search
        post :batch_invite
        get :check_email
      end
      member do
        # Used when adding a person to a cast from a person (or person-like) page
        post :add_to_cast
        post :remove_from_cast
        post :remove_from_organization
        get :contact
        post :send_contact_email
        patch :update_availability
        get :availability_modal
      end
    end

    resources :groups, only: %i[show destroy update] do
      member do
        post :add_to_cast
        post :remove_from_cast
        post :remove_from_organization
        patch :update_availability
        get :availability_modal
      end
    end

    # Email logs are accessed through directory (people/groups)
    scope "/directory" do
      get "/emails/:id", to: "email_logs#show", as: "directory_email"
    end

    resources :locations do
      member do
        get :cannot_delete
      end
    end

    resources :productions, except: [ :new, :create ] do
      member do
        get :confirm_delete
        post :check_url_availability
        patch :update_public_key
        # Production team management
        post :add_team_member
        patch :update_team_permission
        delete :remove_team_member
        delete :revoke_production_invite
      end

      resources :visual_assets, only: [ :index ] do
        collection do
          get :new_poster
          post :create_poster
          get :new_logo
          post :create_logo
        end
        member do
          get :edit_poster
          patch :update_poster
          delete :destroy_poster
          patch :set_primary_poster
          get :edit_logo
          patch :update_logo
        end
      end

      resources :shows do
        collection do
          get :calendar
          get :recurring_series, to: "shows#recurring_series"
          post :extend_series, to: "shows#extend_series"
        end
        member do
          get   :cancel, action: :cancel
          patch :cancel_show
          delete :delete_show
          patch :uncancel
          post :link_show
          delete :unlink_show
          delete :delete_linkage
          post :toggle_signup_based_casting
          post :toggle_attendance
          get :attendance
          patch :update_attendance
          post :create_walkin
          patch :transfer
        end

        # Show-specific custom roles
        resources :show_roles, only: [ :index, :create, :update, :destroy ] do
          collection do
            post :reorder
            post :copy_from_production
            get :talent_pool_members
            get :check_assignments
            post :clear_assignments
            post :toggle_custom_roles
            get :migration_preview
            post :execute_migration
          end
          member do
            get :slot_change_preview
            post :execute_slot_change
          end
        end
      end

      # Note: Most nested routes have been moved to top-level manage routes
      # Only keeping show-specific nested resources that require production context
    end

    # Money / Payouts section - org-level
    get "money", to: "money#index", as: "money_index"
    get "money/financials", to: "money_financials#index", as: "money_financials"
    get "money/financials/:production_id", to: "money_financials#index", as: "money_production_financials"
    get "money/payouts", to: "money_payouts#index", as: "money_payouts"
    get "money/payouts/:production_id", to: "money_payouts#index", as: "money_production_payouts"
    post "money/payouts/:production_id/send_payment_setup_reminders", to: "money_payouts#send_payment_setup_reminders", as: "send_payment_setup_reminders_money_payouts"

    # Advances - production-level
    get "money/advances", to: "advances#index", as: "money_advances"
    get "money/advances/:production_id", to: "advances#index", as: "money_production_advances"
    get "money/advances/:production_id/new", to: "advances#new", as: "new_money_production_advance"
    post "money/advances/:production_id", to: "advances#create", as: "create_money_production_advance"
    get "money/advances/:production_id/:id", to: "advances#show", as: "money_advance"
    patch "money/advances/:production_id/:id", to: "advances#update"
    delete "money/advances/:production_id/:id", to: "advances#destroy", as: "destroy_money_advance"
    post "money/advances/:production_id/:id/write_off", to: "advances#write_off", as: "write_off_money_advance"
    post "money/advances/:production_id/:id/mark_paid", to: "advances#mark_paid", as: "mark_paid_money_advance"
    delete "money/advances/:production_id/:id/mark_paid", to: "advances#unmark_paid", as: "unmark_paid_money_advance"
    # Advance waivers
    post "money/advances/:production_id/waiver", to: "advances#create_waiver", as: "create_money_advance_waiver"
    delete "money/advances/:production_id/waiver/:id", to: "advances#destroy_waiver", as: "destroy_money_advance_waiver"

    # Payroll runs - organization-level (spans all productions)
    get "money/payroll", to: "payroll#index", as: "money_payroll"
    get "money/payroll/settings", to: "payroll#settings", as: "money_payroll_settings"
    patch "money/payroll/settings", to: "payroll#update_settings"
    get "money/payroll/new", to: "payroll#new_run", as: "new_money_payroll_run"
    post "money/payroll", to: "payroll#create_run", as: "create_money_payroll_run"
    post "money/payroll/pay_now", to: "payroll#pay_now", as: "money_payroll_pay_now"
    get "money/payroll/runs/:id", to: "payroll#show_run", as: "money_payroll_run"
    post "money/payroll/runs/:id/start", to: "payroll#start_run", as: "start_money_payroll_run"
    post "money/payroll/runs/:id/cancel", to: "payroll#cancel_run", as: "cancel_money_payroll_run"
    post "money/payroll/runs/:id/complete", to: "payroll#complete_run", as: "complete_money_payroll_run"
    # Payroll line items
    post "money/payroll/runs/:run_id/line_items/:id/pay", to: "payroll#mark_line_item_paid", as: "pay_money_payroll_line_item"
    post "money/payroll/runs/:run_id/line_items/:id/unpay", to: "payroll#unmark_line_item_paid", as: "unpay_money_payroll_line_item"

    # Show financials - the main financial data view for a show
    get "money/shows/:id/financials", to: "show_financials#show", as: "money_show_financials"
    get "money/shows/:id/financials/edit", to: "show_financials#edit", as: "edit_money_show_financials"
    patch "money/shows/:id/financials", to: "show_financials#update", as: "update_money_show_financials"
    post "money/shows/:id/financials/mark_non_revenue", to: "show_financials#mark_non_revenue", as: "mark_non_revenue_money_show_financials"
    post "money/shows/:id/financials/unmark_non_revenue", to: "show_financials#unmark_non_revenue", as: "unmark_non_revenue_money_show_financials"

    # Expense items - receipt management
    post "money/expense_items/:id/upload_receipt", to: "expense_items#upload_receipt", as: "upload_receipt_expense_item"
    delete "money/expense_items/:id/remove_receipt", to: "expense_items#remove_receipt", as: "remove_receipt_expense_item"

    # Payout schemes - explicitly named for manage_production_money_payout_scheme(s)_path pattern
    get "money/schemes", to: "payout_schemes#index", as: "money_payout_schemes"
    post "money/schemes", to: "payout_schemes#create"
    get "money/schemes/new", to: "payout_schemes#new", as: "new_money_payout_scheme"
    get "money/schemes/presets", to: "payout_schemes#presets", as: "presets_money_payout_schemes"
    post "money/schemes/create_from_preset", to: "payout_schemes#create_from_preset", as: "create_from_preset_money_payout_schemes"
    get "money/schemes/:id", to: "payout_schemes#show", as: "money_payout_scheme"
    get "money/schemes/:id/edit", to: "payout_schemes#edit", as: "edit_money_payout_scheme"
    patch "money/schemes/:id", to: "payout_schemes#update"
    put "money/schemes/:id", to: "payout_schemes#update"
    delete "money/schemes/:id", to: "payout_schemes#destroy"
    post "money/schemes/:id/make_default", to: "payout_schemes#make_default", as: "make_default_money_payout_scheme"
    get "money/schemes/:id/preview", to: "payout_schemes#preview", as: "preview_money_payout_scheme"

    # Ticket fee templates
    resources :ticket_fee_templates, only: [ :index, :create, :update, :destroy ], path: "money/fees"

    # ===========================================
    # TICKETING SECTION (mirrors Money section structure)
    # ===========================================

    # Main ticketing hub (organization level)
    get "ticketing", to: "ticketing#index", as: "ticketing_index"

    # Provider management
    get  "ticketing/providers",          to: "ticketing_providers#index",   as: "ticketing_providers"
    get  "ticketing/providers/new",      to: "ticketing_provider_wizard#platform", as: "ticketing_providers_new"
    get  "ticketing/providers/:id",      to: "ticketing_providers#show",    as: "ticketing_provider"
    get  "ticketing/providers/:id/edit", to: "ticketing_providers#edit",    as: "edit_ticketing_provider"
    patch "ticketing/providers/:id",     to: "ticketing_providers#update"
    delete "ticketing/providers/:id",    to: "ticketing_providers#destroy"
    post "ticketing/providers/:id/test", to: "ticketing_providers#test",    as: "test_ticketing_provider"
    post "ticketing/providers/:id/sync", to: "ticketing_providers#sync",    as: "sync_ticketing_provider"

    # Provider wizard (connect new platform)
    get  "ticketing/wizard",             to: "ticketing_provider_wizard#platform",         as: "ticketing_wizard"
    post "ticketing/wizard/platform",    to: "ticketing_provider_wizard#save_platform",    as: "ticketing_wizard_save_platform"
    get  "ticketing/wizard/credentials", to: "ticketing_provider_wizard#credentials",      as: "ticketing_wizard_credentials"
    post "ticketing/wizard/credentials", to: "ticketing_provider_wizard#save_credentials", as: "ticketing_wizard_save_credentials"
    get  "ticketing/wizard/test",        to: "ticketing_provider_wizard#test",             as: "ticketing_wizard_test"
    post "ticketing/wizard/retry",       to: "ticketing_provider_wizard#retry_test",       as: "ticketing_wizard_retry"
    get  "ticketing/wizard/review",      to: "ticketing_provider_wizard#review",           as: "ticketing_wizard_review"
    post "ticketing/wizard/create",      to: "ticketing_provider_wizard#create_provider",  as: "ticketing_wizard_create"
    delete "ticketing/wizard/cancel",    to: "ticketing_provider_wizard#cancel",           as: "ticketing_wizard_cancel"

    # Pending events (events that need manual linking)
    get  "ticketing/pending",     to: "ticketing_pending_events#index", as: "ticketing_pending_events"
    get  "ticketing/pending/:id", to: "ticketing_pending_events#show",  as: "ticketing_pending_event"
    post "ticketing/pending/:id/link",    to: "ticketing_pending_events#link",    as: "link_ticketing_pending_event"
    post "ticketing/pending/:id/dismiss", to: "ticketing_pending_events#dismiss", as: "dismiss_ticketing_pending_event"
    post "ticketing/sync/:provider_id",   to: "ticketing_pending_events#sync_now", as: "ticketing_sync_now"

    # Production-level ticketing (like /money/financials/:production_id)
    get "ticketing/:production_id", to: "ticketing_productions#show", as: "ticketing_production"

    # Production links (events linked to this production)
    scope "ticketing/:production_id" do
      get  "links",                   to: "ticketing_production_links#index",         as: "ticketing_production_links"
      get  "links/new",               to: "ticketing_production_links#new",           as: "new_ticketing_production_link"
      post "links",                   to: "ticketing_production_links#create",        as: "create_ticketing_production_link"
      get  "links/:id",               to: "ticketing_production_links#show",          as: "ticketing_production_link"
      get  "links/:id/edit",          to: "ticketing_production_links#edit",          as: "edit_ticketing_production_link"
      patch "links/:id",              to: "ticketing_production_links#update",        as: "update_ticketing_production_link"
      delete "links/:id",             to: "ticketing_production_links#destroy",       as: "destroy_ticketing_production_link"
      post "links/:id/sync",          to: "ticketing_production_links#sync",          as: "sync_ticketing_production_link"
      get  "links/:id/match",         to: "ticketing_production_links#match",         as: "match_ticketing_production_link"
      post "links/:id/apply_matches", to: "ticketing_production_links#apply_matches", as: "apply_matches_ticketing_production_link"
    end

    # Production expenses (amortized costs spread across shows)
    # Nested under /money/financials/:production_id/expenses
    scope "money/financials/:production_id" do
      get  "expenses", to: "production_expenses#index", as: "money_financials_production_expenses"
      get  "expenses/new", to: "production_expenses#new", as: "new_money_financials_production_expense"
      post "expenses", to: "production_expenses#create", as: "create_money_financials_production_expense"
      get  "expenses/:id", to: "production_expenses#show", as: "money_financials_production_expense"
      get  "expenses/:id/edit", to: "production_expenses#edit", as: "edit_money_financials_production_expense"
      patch "expenses/:id", to: "production_expenses#update", as: "update_money_financials_production_expense"
      delete "expenses/:id", to: "production_expenses#destroy", as: "delete_money_financials_production_expense"
      post "expenses/:id/recalculate", to: "production_expenses#recalculate", as: "recalculate_money_financials_production_expense"
      patch "expenses/:id/allocations/:allocation_id/override", to: "production_expenses#override_allocation", as: "override_money_financials_production_expense_allocation"
    end

    # Contracts - third-party productions and venue rentals
    resources :contracts, path: "money/contracts" do
      member do
        post :activate
        get :cancel
        post :process_cancel
        # Amend contract flow with nested paths
        get "amend/bookings", action: :amend_bookings, as: :amend_bookings
        post "amend/bookings", action: :save_amend_bookings, as: :save_amend_bookings
        get "amend/events", action: :amend_events, as: :amend_events
        get "amend/payments", action: :amend_payments, as: :amend_payments
        post "amend/payments", action: :save_amend_payments, as: :save_amend_payments
        get "amend/review", action: :amend_review, as: :amend_review
        post "amend/apply", action: :apply_amendments, as: :apply_amendments
      end
      resources :contract_documents, only: %i[create destroy], path: "documents"
      resources :contract_payments, only: %i[create update destroy], path: "payments" do
        member do
          post :mark_paid
        end
      end
      resources :space_rentals, only: %i[create update destroy], path: "rentals"
    end

    # Contract wizard
    get  "money/contracts/wizard/new", to: "contract_wizard#new", as: "new_contract_wizard"
    post "money/contracts/wizard/create_draft", to: "contract_wizard#create_draft", as: "create_draft_contract_wizard"
    get  "money/contracts/:contract_id/wizard/resume", to: "contract_wizard#resume", as: "resume_contract_wizard"
    get  "money/contracts/:contract_id/wizard/contractor", to: "contract_wizard#contractor", as: "contractor_contract_wizard"
    post "money/contracts/:contract_id/wizard/contractor", to: "contract_wizard#save_contractor"
    get  "money/contracts/:contract_id/wizard/bookings", to: "contract_wizard#bookings", as: "bookings_contract_wizard"
    post "money/contracts/:contract_id/wizard/bookings", to: "contract_wizard#save_bookings"
    get  "money/contracts/:contract_id/wizard/schedule_preview", to: "contract_wizard#schedule_preview", as: "schedule_preview_contract_wizard"
    post "money/contracts/:contract_id/wizard/schedule_preview", to: "contract_wizard#save_schedule_preview"
    get  "money/contracts/:contract_id/wizard/services", to: "contract_wizard#services", as: "services_contract_wizard"
    post "money/contracts/:contract_id/wizard/services", to: "contract_wizard#save_services"
    get  "money/contracts/:contract_id/wizard/payments", to: "contract_wizard#payments", as: "payments_contract_wizard"
    post "money/contracts/:contract_id/wizard/payments", to: "contract_wizard#save_payments"
    get  "money/contracts/:contract_id/wizard/terms", to: "contract_wizard#terms", as: "terms_contract_wizard"
    post "money/contracts/:contract_id/wizard/terms", to: "contract_wizard#save_terms"
    get  "money/contracts/:contract_id/wizard/documents", to: "contract_wizard#documents", as: "documents_contract_wizard"
    post "money/contracts/:contract_id/wizard/documents", to: "contract_wizard#save_documents"
    delete "money/contracts/:contract_id/wizard/documents/:document_id", to: "contract_wizard#delete_document", as: "delete_document_contract_wizard"
    get  "money/contracts/:contract_id/wizard/review", to: "contract_wizard#review", as: "review_contract_wizard"
    post "money/contracts/:contract_id/wizard/activate", to: "contract_wizard#activate", as: "activate_contract_wizard"
    delete "money/contracts/:contract_id/wizard/cancel", to: "contract_wizard#cancel", as: "cancel_contract_wizard"

    # Location spaces
    scope "locations/:location_id" do
      resources :location_spaces, path: "spaces", only: %i[index create update destroy] do
        member do
          post :set_default
        end
      end
    end

    # Show payouts - now under /money/shows/:id/payouts
    get "money/shows/:id/payouts", to: "show_payouts#show", as: "money_show_payout"
    patch "money/shows/:id/payouts", to: "show_payouts#update"
    put "money/shows/:id/payouts", to: "show_payouts#update"
    post "money/shows/:id/payouts/calculate", to: "show_payouts#calculate", as: "calculate_money_show_payout"
    post "money/shows/:id/payouts/mark_paid", to: "show_payouts#mark_paid", as: "mark_paid_money_show_payout"
    get "money/shows/:id/payouts/override", to: "show_payouts#override", as: "override_money_show_payout"
    patch "money/shows/:id/payouts/save_override", to: "show_payouts#save_override", as: "save_override_money_show_payout"
    delete "money/shows/:id/payouts/clear_override", to: "show_payouts#clear_override", as: "clear_override_money_show_payout"
    get "money/shows/:id/payouts/change_scheme", to: "show_payouts#change_scheme", as: "change_scheme_money_show_payout"
    patch "money/shows/:id/payouts/apply_scheme_change", to: "show_payouts#apply_scheme_change", as: "apply_scheme_change_money_show_payout"
    post "money/shows/:id/payouts/line_items/:line_item_id/mark_paid", to: "show_payouts#mark_line_item_paid", as: "mark_line_item_paid_money_show_payout"
    delete "money/shows/:id/payouts/line_items/:line_item_id/mark_paid", to: "show_payouts#unmark_line_item_paid", as: "unmark_line_item_paid_money_show_payout"
    post "money/shows/:id/payouts/mark_all_offline", to: "show_payouts#mark_all_offline", as: "mark_all_offline_money_show_payout"
    post "money/shows/:id/payouts/send_payment_reminders", to: "show_payouts#send_payment_reminders", as: "send_payment_reminders_money_show_payout"
    post "money/shows/:id/payouts/close_as_non_paying", to: "show_payouts#close_as_non_paying", as: "close_as_non_paying_money_show_payout"
    post "money/shows/:id/payouts/reopen", to: "show_payouts#reopen", as: "reopen_money_show_payout"
    post "money/shows/:id/payouts/add_line_item", to: "show_payouts#add_line_item", as: "add_line_item_money_show_payout"
    delete "money/shows/:id/payouts/line_items/:line_item_id", to: "show_payouts#remove_line_item", as: "remove_line_item_money_show_payout"
    post "money/shows/:id/payouts/add_missing_cast", to: "show_payouts#add_missing_cast", as: "add_missing_cast_money_show_payout"
    post "money/shows/:id/payouts/update_guest_payments", to: "show_payouts#update_guest_payments", as: "update_guest_payments_money_show_payout"
    # Show advances - issue advances to cast members for a show
    post "money/shows/:id/payouts/issue_advances", to: "show_payouts#issue_advances", as: "issue_advances_money_show_payout"
    # Reset calculation - clear calculated state and line items
    delete "money/shows/:id/payouts/reset_calculation", to: "show_payouts#reset_calculation", as: "reset_calculation_money_show_payout"

    resources :cast_assignment_stages, only: %i[create update destroy]
    # resources :email_groups, only: %i[create update destroy] (moved to communications)
    # resources :audition_email_assignments, only: %i[create update destroy] (moved to communications)
    # Note: auditions routes are now under signups/auditions
  end

  # Used for adding people and removing them from an audition session (outside manage namespace)
  namespace :manage do
    post "/auditions/add_to_session",       to: "auditions#add_to_session"
    post "/auditions/remove_from_session",  to: "auditions#remove_from_session"
    post "/auditions/move_to_session",      to: "auditions#move_to_session"
  end

  # Junkers
  get "/wp-admin/*", to: proc { [ 200, {}, [ "" ] ] }
  get "/wp-include/*", to: proc { [ 200, {}, [ "" ] ] }
  get "/.well-known/appspecific/*path", to: proc { [ 204, {}, [] ] }

  # Vacancy flow (cast member can't make it to a show)
  scope "/vacancy/:show_id" do
    get "/",        to: "vacancy#show",    as: "vacancy"
    post "/confirm", to: "vacancy#confirm", as: "vacancy_confirm"
    get "/success",  to: "vacancy#success", as: "vacancy_success"
  end

  # Claim vacancy flow (invited person claims a role)
  scope "/claim/:token" do
    get "/",        to: "claim_vacancy#show",    as: "claim_vacancy"
    post "/claim",  to: "claim_vacancy#claim",   as: "do_claim_vacancy"
    post "/decline", to: "claim_vacancy#decline", as: "decline_claim_vacancy"
    get "/success", to: "claim_vacancy#success", as: "claim_vacancy_success"
  end

  # Profile routes (top-level) - supports optional :person_id for multi-profile editing
  get    "/profile",         to: "profile#index",   as: "profile"
  get    "/profile/welcome", to: "profile#welcome", as: "profile_welcome"
  post   "/profile/dismiss_welcome", to: "profile#dismiss_welcome", as: "dismiss_profile_welcome"
  post   "/profile/mark_welcomed", to: "profile#mark_welcomed", as: "mark_profile_welcomed"
  patch  "/profile", to: "profile#update"  # Fallback for requests without ID (uses default profile)
  patch  "/profile/visibility", to: "profile#update_visibility", as: "update_profile_visibility"
  patch  "/profile/headshots/:id/set_primary", to: "profile#set_primary_headshot", as: "set_primary_headshot"
  get    "/profile/public", to: "profile#public", as: "profile_public"
  get    "/profile/search_groups", to: "profile#search_groups", as: "search_groups_profile"
  post   "/profile/join_group", to: "profile#join_group", as: "join_group_profile"
  delete "/profile/leave_group/:id", to: "profile#leave_group", as: "leave_group_profile"
  patch  "/profile/toggle_group_visibility", to: "profile#toggle_group_visibility", as: "toggle_group_visibility_profile"

  # Profile routes with ID (for editing specific profiles)
  get    "/profile/:id", to: "profile#show", as: "edit_profile", constraints: { id: /\d+/ }
  patch  "/profile/:id", to: "profile#update", as: "update_profile", constraints: { id: /\d+/ }
  get    "/profile/:id/change-url", to: "profile#change_url", as: "change_url_profile", constraints: { id: /\d+/ }
  post   "/profile/:id/check-url-availability", to: "profile#check_url_availability", as: "check_url_availability_profile", constraints: { id: /\d+/ }
  patch  "/profile/:id/update-url", to: "profile#update_url", as: "update_url_profile", constraints: { id: /\d+/ }
  get    "/profile/:id/change-email", to: "profile#change_email", as: "change_email_profile", constraints: { id: /\d+/ }
  patch  "/profile/:id/change-email", to: "profile#update_email", as: "update_email_profile", constraints: { id: /\d+/ }

  # Groups routes (top-level, use profile layout)
  get    "/groups",                   to: "groups#index",      as: "groups"
  get    "/groups/new",               to: "groups#new",        as: "new_group"
  post   "/groups",                   to: "groups#create",     as: "create_group"
  patch  "/groups/:group_id/headshots/:id/set_primary", to: "groups#set_primary_headshot",
                                                        as: "set_primary_group_headshot"
  post   "/groups/:id/check-url-availability", to: "groups#check_url_availability", as: "check_url_availability_group"
  patch  "/groups/:id/update-url", to: "groups#update_url", as: "update_url_group"
  patch  "/groups/:id/visibility", to: "groups#update_visibility", as: "update_group_visibility"
  get    "/groups/:id",               to: "groups#edit",       as: "edit_group"
  get    "/groups/:id/settings",      to: "groups#settings",   as: "settings_group"
  patch  "/groups/:id",               to: "groups#update",     as: "update_group"
  patch  "/groups/:id/update_member_role", to: "groups#update_member_role", as: "update_member_role_group"
  delete "/groups/:id/remove_member", to: "groups#remove_member", as: "remove_member_group"
  patch  "/groups/:id/update_member_notifications", to: "groups#update_member_notifications",
                                                    as: "update_member_notifications_group"
  patch  "/groups/:id/archive",       to: "groups#archive",    as: "archive_group"
  patch  "/groups/:id/unarchive",     to: "groups#unarchive",  as: "unarchive_group"

  # Group invitations
  post "/groups/:group_id/invitations", to: "group_invitations#create", as: "group_invitations"
  delete "/groups/:group_id/invitations/:id", to: "group_invitations#revoke", as: "revoke_group_invitation"
  get "/group_invitations/:token/accept", to: "group_invitations#accept", as: "accept_group_invitation"
  post "/group_invitations/:token/accept", to: "group_invitations#do_accept", as: "do_accept_group_invitation"

  # Public profiles (must be last to catch any remaining paths)
  get "/:public_key/shoutouts", to: "public_profiles#shoutouts", as: "public_profile_shoutouts",
                                constraints: { public_key: /[a-z0-9][a-z0-9-]{2,29}/ }
  get "/:public_key/:show_id", to: "public_profiles#production_show", as: "public_profile_show",
                               constraints: { public_key: /[a-z0-9][a-z0-9-]{2,29}/, show_id: /\d+/ }
  get "/:public_key", to: "public_profiles#show", as: "public_profile",
                      constraints: { public_key: /[a-z0-9][a-z0-9-]{2,29}/ }
end
