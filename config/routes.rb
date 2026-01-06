# frozen_string_literal: true

Rails.application.routes.draw do
  root "home#index"

  # Utility
  get "/up", to: proc { [ 200, {}, [ "OK" ] ] }

  # Landing page
  get "home/index"

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
    get  "/organizations",      to: "superadmin#organizations_list",  as: "organizations_list"
    get  "/organizations/:id",  to: "superadmin#organization_detail", as: "organization_detail"
    get  "/storage",            to: "superadmin#storage",             as: "storage_monitor"
    post "/storage/cleanup_orphans", to: "superadmin#storage_cleanup_orphans", as: "storage_cleanup_orphans"
    post "/storage/cleanup_legacy",  to: "superadmin#storage_cleanup_legacy",  as: "storage_cleanup_legacy"
    post "/storage/migrate_keys",    to: "superadmin#storage_migrate_keys",    as: "storage_migrate_keys"
    post "/storage/cleanup_s3_orphans", to: "superadmin#storage_cleanup_s3_orphans", as: "storage_cleanup_s3_orphans"
    get  "/data",               to: "superadmin#data",                as: "data_monitor"
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

  # Selection interface (under manage namespace)
  scope "/select" do
    get  "/organization",        to: "manage/select#organization",     as: "select_organization"
    post "/organization",        to: "manage/select#set_organization", as: "set_organization"
    get  "/production",          to: "manage/select#production",       as: "select_production"
    post "/production",          to: "manage/select#set_production",   as: "set_production"
  end

  # Talent-facing interface
  namespace :my do
    get   "/",                              to: "dashboard#index",          as: "dashboard"
    get   "/welcome",                       to: "dashboard#welcome",        as: "welcome"
    post  "/dismiss_welcome",               to: "dashboard#dismiss_welcome", as: "dismiss_welcome"

    # Profile management
    resources :profiles, only: [ :index, :new, :create ]

    # Productions
    get    "/productions",                  to: "productions#index",        as: "productions"
    get    "/productions/:id",              to: "productions#show",         as: "production"
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
    get   "/audition_requests",             to: "audition_requests#index",  as: "audition_requests"
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

    # Messages (inbox for talent)
    get   "/messages",                          to: "messages#index",                     as: "messages"
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

    # Directory - unified people and groups listing
    get  "/directory",          to: "directory#index", as: "directory"
    post "/directory/contact",  to: "directory#contact_directory", as: "contact_directory"
    patch "/directory/group/:id/update_availability", to: "directory#update_group_availability",
                                                      as: "update_group_availability"

    resources :organizations do
      collection do
        get :setup_guide
      end
      member do
        get :confirm_delete
        post :transfer_ownership
        delete :remove_logo
      end
    end

    resources :team, only: [ :index ] do
      collection do
        post :invite
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
      end
    end

    resources :groups, only: %i[show destroy update] do
      member do
        post :add_to_cast
        post :remove_from_cast
        post :remove_from_organization
        patch :update_availability
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

    resources :productions do
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

      resources :availability, only: %i[index show] do
        member do
          patch :update_show_availability
        end
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
        end
        member do
          get   :cancel, action: :cancel
          patch :cancel_show
          delete :delete_show
          patch :uncancel
          post :link_show
          delete :unlink_show
          delete :delete_linkage
        end

        # Show-specific custom roles
        resources :show_roles, only: [ :index, :create, :update, :destroy ] do
          collection do
            post :reorder
            post :copy_from_production
            get :talent_pool_members
            get :check_assignments
            post :clear_assignments
          end
        end
      end

      # Single talent pool per production - no CRUD, just member management
      resources :talent_pools, path: "talent-pools", only: %i[index] do
        collection do
          get :search_people
          post :add_person
          get "confirm-remove-person/:person_id", action: :confirm_remove_person, as: :confirm_remove_person
          post :remove_person
          post :add_group
          get "confirm-remove-group/:group_id", action: :confirm_remove_group, as: :confirm_remove_group
          post :remove_group
        end
      end

      # Casting routes - manage roles and cast assignments
      get "casting", to: "casting#index", as: "casting"

      resources :roles do
        collection do
          post :reorder
        end
      end

      # Show cast assignment
      get "casting/shows/:show_id/cast", to: "casting#show_cast", as: "show_cast"
      get "casting/shows/:show_id/contact", to: "casting#contact_cast", as: "show_contact_cast"
      post "casting/shows/:show_id/contact", to: "casting#send_cast_email", as: "send_cast_email"
      post "casting/shows/:show_id/assign_person_to_role", to: "casting#assign_person_to_role"
      post "casting/shows/:show_id/assign_guest_to_role", to: "casting#assign_guest_to_role"
      post "casting/shows/:show_id/remove_person_from_role", to: "casting#remove_person_from_role"
      post "casting/shows/:show_id/create_vacancy", to: "casting#create_vacancy", as: "create_vacancy"
      post "casting/shows/:show_id/finalize", to: "casting#finalize_casting", as: "finalize_casting"
      patch "casting/shows/:show_id/reopen", to: "casting#reopen_casting", as: "reopen_casting"
      post "casting/shows/:show_id/copy_cast_to_linked", to: "casting#copy_cast_to_linked", as: "copy_cast_to_linked"

      # Vacancies management (detail and actions only - no index)
      resources :vacancies, only: %i[show] do
        member do
          post :send_invitations
          post :cancel
          post :fill
        end
        resources :invitations, only: [], controller: "vacancy_invitations" do
          member do
            post :resend
          end
        end
      end

      # Audition cycle creation wizard
      scope "audition-wizard", as: "audition_wizard" do
        get    "/",           to: "audition_cycle_wizard#format",          as: "format"
        post   "format",      to: "audition_cycle_wizard#save_format",     as: "save_format"
        get    "schedule",    to: "audition_cycle_wizard#schedule",        as: "schedule"
        post   "schedule",    to: "audition_cycle_wizard#save_schedule",   as: "save_schedule"
        get    "sessions",    to: "audition_cycle_wizard#sessions",        as: "sessions"
        post   "sessions",    to: "audition_cycle_wizard#save_sessions",   as: "save_sessions"
        post   "sessions/generate", to: "audition_cycle_wizard#generate_sessions", as: "generate_sessions"
        post   "sessions/add", to: "audition_cycle_wizard#add_session",    as: "add_session"
        patch  "sessions/:session_index", to: "audition_cycle_wizard#update_session", as: "update_session"
        delete "sessions/:session_index", to: "audition_cycle_wizard#delete_session", as: "delete_session"
        get    "availability", to: "audition_cycle_wizard#availability",   as: "availability"
        post   "availability", to: "audition_cycle_wizard#save_availability", as: "save_availability"
        get    "reviewers",   to: "audition_cycle_wizard#reviewers",       as: "reviewers"
        post   "reviewers",   to: "audition_cycle_wizard#save_reviewers",  as: "save_reviewers"
        get    "voting",      to: "audition_cycle_wizard#voting",          as: "voting"
        post   "voting",      to: "audition_cycle_wizard#save_voting",     as: "save_voting"
        get    "review",      to: "audition_cycle_wizard#review",          as: "review"
        post   "create",      to: "audition_cycle_wizard#create_cycle",    as: "create_cycle"
        delete "cancel",      to: "audition_cycle_wizard#cancel",          as: "cancel"
      end

      resources :audition_cycles do
        resources :audition_requests do
          member do
            get   "edit_answers",       to: "audition_requests#edit_answers", as: "edit_answers"
            get   "edit_video",         to: "audition_requests#edit_video",   as: "edit_video"
            patch "update_audition_session_availability", to: "audition_requests#update_audition_session_availability", as: "update_audition_session_availability"
            post  "cast_vote",          to: "audition_requests#cast_vote",    as: "cast_vote"
            get   "votes",              to: "audition_requests#votes",        as: "votes"
          end
        end
        resources :audition_sessions do
          resources :auditions, only: [ :show ] do
            member do
              post "cast_vote", to: "auditions#cast_audition_vote", as: "cast_vote"
            end
          end
        end
        member do
          get    "auditions", to: "auditions#schedule_auditions", as: "schedule_auditions"
          get    "form",              to: "audition_cycles#form",              as: "form"
          get    "preview",           to: "audition_cycles#preview",           as: "preview"
          post   "create_question",   to: "audition_cycles#create_question",   as: "create_question"
          patch  "update_question/:question_id", to: "audition_cycles#update_question", as: "update_question"
          delete "destroy_question/:question_id", to: "audition_cycles#destroy_question", as: "destroy_question"
          post   "reorder_questions", to: "audition_cycles#reorder_questions", as: "reorder_questions"
          patch  "archive",           to: "audition_cycles#archive",           as: "archive"
          get    "delete_confirm",    to: "audition_cycles#delete_confirm",    as: "delete_confirm"
          patch  "toggle_voting",     to: "audition_cycles#toggle_voting",     as: "toggle_voting"
          get    "prepare",           to: "auditions#prepare",                   as: "prepare"
          patch  "update_reviewers",  to: "auditions#update_reviewers",          as: "update_reviewers"
          get    "publicize",         to: "auditions#publicize",                 as: "publicize"
          get    "review",            to: "auditions#review",                    as: "review"
          patch  "finalize_invitations", to: "auditions#finalize_invitations", as: "finalize_invitations"
          get    "run",               to: "auditions#run",                       as: "run"
          get    "casting",           to: "auditions#casting",                   as: "casting"
          get    "casting/select",    to: "auditions#casting_select", as: "casting_select"
          post   "add_to_cast_assignment", to: "auditions#add_to_cast_assignment", as: "add_to_cast_assignment"
          post   "remove_from_cast_assignment", to: "auditions#remove_from_cast_assignment",
                                                as: "remove_from_cast_assignment"
          post   "finalize_and_notify", to: "auditions#finalize_and_notify", as: "finalize_and_notify"
          post   "finalize_and_notify_invitations", to: "auditions#finalize_and_notify_invitations",
                                                    as: "finalize_and_notify_invitations"
        end
      end

      resources :questionnaires do
        member do
          get    "form",              to: "questionnaires#form",              as: "form"
          get    "preview",           to: "questionnaires#preview",           as: "preview"
          post   "create_question",   to: "questionnaires#create_question",   as: "create_question"
          patch  "update_question/:question_id", to: "questionnaires#update_question", as: "update_question"
          delete "destroy_question/:question_id", to: "questionnaires#destroy_question", as: "destroy_question"
          post   "reorder_questions", to: "questionnaires#reorder_questions", as: "reorder_questions"
          post   "invite_people",     to: "questionnaires#invite_people",     as: "invite_people"
          patch  "archive",           to: "questionnaires#archive",           as: "archive"
          patch  "unarchive",         to: "questionnaires#unarchive",         as: "unarchive"
          get    "responses",         to: "questionnaires#responses",         as: "responses"
          get    "responses/:response_id", to: "questionnaires#show_response",    as: "response"
        end
      end

      # Sign-up forms for events
      resources :sign_up_forms, path: "sign-ups" do
        member do
          get    "slots",             to: "sign_up_forms#slots",             as: "slots"
          post   "create_slot",       to: "sign_up_forms#create_slot",       as: "create_slot"
          patch  "update_slot/:slot_id", to: "sign_up_forms#update_slot",    as: "update_slot"
          delete "destroy_slot/:slot_id", to: "sign_up_forms#destroy_slot",  as: "destroy_slot"
          post   "reorder_slots",     to: "sign_up_forms#reorder_slots",     as: "reorder_slots"
          post   "generate_slots",    to: "sign_up_forms#generate_slots",    as: "generate_slots"
          patch  "toggle_slot_hold/:slot_id", to: "sign_up_forms#toggle_slot_hold", as: "toggle_slot_hold"
          get    "holdouts",          to: "sign_up_forms#holdouts",          as: "holdouts"
          post   "create_holdout",    to: "sign_up_forms#create_holdout",    as: "create_holdout"
          delete "destroy_holdout/:holdout_id", to: "sign_up_forms#destroy_holdout", as: "destroy_holdout"
          get    "questions",         to: "sign_up_forms#questions",         as: "questions"
          post   "create_question",   to: "sign_up_forms#create_question",   as: "create_question"
          patch  "update_question/:question_id", to: "sign_up_forms#update_question", as: "update_question"
          delete "destroy_question/:question_id", to: "sign_up_forms#destroy_question", as: "destroy_question"
          post   "reorder_questions", to: "sign_up_forms#reorder_questions", as: "reorder_questions"
          get    "registrations",     to: "sign_up_forms#registrations",     as: "registrations"
          post   "register",          to: "sign_up_forms#register",          as: "register"
          delete "cancel_registration/:registration_id", to: "sign_up_forms#cancel_registration", as: "cancel_registration"
          get    "preview",           to: "sign_up_forms#preview",           as: "preview"
          patch  "toggle_active",     to: "sign_up_forms#toggle_active",     as: "toggle_active"
        end
      end

      get "/audition_sessions/summary", to: "audition_sessions#summary", as: "audition_session_summary"

      resources :communications, only: %i[index show] do
        collection do
          post :send_message
        end
      end

      resources :cast_assignment_stages, only: %i[create update destroy]
      # resources :email_groups, only: %i[create update destroy] (removed)
      resources :audition_email_assignments, only: %i[create update destroy]
      resources :auditions do
        collection do
          get :archive
        end
      end
    end

    # Used for adding people and removing them from an audition session
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
