Rails.application.routes.draw do
  root "home#index"

  # Utility
  get "/up", to: proc { [ 200, {}, [ "OK" ] ] }

  # API endpoints
  namespace :api do
    get "/search/people_and_groups", to: "search#people_and_groups"
    get "/check_existing_shoutout", to: "search#check_existing_shoutout"
  end

  # Landing page
  get "home/index"
  post "/notify_me", to: "home#notify_me", as: "notify_me"
  get "/notify_me/success", to: "home#notify_me_success", as: "notify_me_success"

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

  # God mode
  scope "/god_mode" do
    get  "/",                   to: "god_mode#index",               as: "god_mode"
    post "/impersonate",        to: "god_mode#impersonate",         as: "impersonate_user"
    post "/stop_impersonating", to: "god_mode#stop_impersonating",  as: "stop_impersonating_user"
    post "/change_email",       to: "god_mode#change_email",        as: "change_email_user"
    get  "/email_logs",         to: "god_mode#email_logs",          as: "email_logs"
    get  "/email_logs/:id",     to: "god_mode#email_log",           as: "email_log"
    get  "/queue",              to: "god_mode#queue",               as: "queue_monitor"
    get  "/queue/failed",       to: "god_mode#queue_failed",        as: "queue_failed"
    post "/queue/retry/:id",    to: "god_mode#queue_retry",         as: "queue_retry"
    delete "/queue/job/:id",    to: "god_mode#queue_delete_job",    as: "queue_delete_job"
    delete "/queue/clear_failed", to: "god_mode#queue_clear_failed", as: "queue_clear_failed"
    delete "/queue/clear_pending", to: "god_mode#queue_clear_pending", as: "queue_clear_pending"
  end

  # Pilot user setup (gods only)
  get "/pilot", to: "pilot#index", as: "pilot"
  post "/pilot/create_talent", to: "pilot#create_talent", as: "pilot_create_talent"
  post "/pilot/create_producer_user", to: "pilot#create_producer_user", as: "pilot_create_producer_user"
  post "/pilot/create_producer_org", to: "pilot#create_producer_org", as: "pilot_create_producer_org"
  post "/pilot/create_producer_location", to: "pilot#create_producer_location", as: "pilot_create_producer_location"
  post "/pilot/create_producer_production", to: "pilot#create_producer_production", as: "pilot_create_producer_production"
  post "/pilot/create_producer_show", to: "pilot#create_producer_show", as: "pilot_create_producer_show"
  post "/pilot/create_producer_additional", to: "pilot#create_producer_additional", as: "pilot_create_producer_additional"
  post "/pilot/resend_invitation", to: "pilot#resend_invitation", as: "pilot_resend_invitation"
  post "/pilot/reset_talent", to: "pilot#reset_talent", as: "pilot_reset_talent"
  post "/pilot/reset_producer", to: "pilot#reset_producer", as: "pilot_reset_producer"

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
    get   "/shows",                         to: "shows#index",              as: "shows"
    get   "/shows/calendar",                to: "shows#calendar",           as: "shows_calendar"
    get   "/shows/:id",                     to: "shows#show",               as: "show"
    get   "/availability",                  to: "availability#index",       as: "availability"
    get   "/availability/calendar",         to: "availability#calendar",    as: "availability_calendar"
    patch "/availability/:show_id",         to: "availability#update",      as: "update_availability"
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

    # Shoutouts management
    get   "/shoutouts",                         to: "shoutouts#index",     as: "shoutouts"
    post  "/shoutouts",                         to: "shoutouts#create",    as: "create_shoutout"
  end

  # Management interface
  namespace :manage do
    get  "/",                              to: "manage#index"
    get  "/welcome",                       to: "manage#welcome",                    as: "welcome"
    post "/dismiss_production_welcome",    to: "manage#dismiss_production_welcome", as: "dismiss_production_welcome"

    # Directory - unified people and groups listing
    get  "/directory",          to: "directory#index",        as: "directory"
    post "/directory/contact",  to: "directory#contact_directory", as: "contact_directory"
    patch "/directory/group/:id/update_availability", to: "directory#update_group_availability", as: "update_group_availability"

    resources :organizations do
      collection do
        get :setup_guide
      end
      member do
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
        patch :update_global_role
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

    resources :people, except: [] do
      collection do
        get :search
        post :batch_invite
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

    resources :groups, only: %i[show destroy] do
      member do
        post :add_to_cast
        post :remove_from_cast
        post :remove_from_organization
        patch :update_availability
      end
    end

    resources :locations do
      member do
        get :cannot_delete
      end
    end

    resources :productions do
      resources :availability, only: [ :index, :show ] do
        collection do
          get  :request_availability
          post :handle_request_availability
        end
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
        end
      end

      resources :talent_pools, path: "talent-pools" do
        collection do
          get :search_people
        end
        member do
          # These are used when dragging and dropping on the talent pool members list or adding from search
          post :add_person
          post :remove_person
          post :add_group
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
      post "casting/shows/:show_id/remove_person_from_role", to: "casting#remove_person_from_role"

      resources :audition_cycles do
        resources :audition_requests do
          member do
            get   "edit_answers",       to: "audition_requests#edit_answers", as: "edit_answers"
            get   "edit_video",         to: "audition_requests#edit_video",   as: "edit_video"
            post  "set_status/:status", to: "audition_requests#set_status",   as: "set_status"
          end
        end
        resources :audition_sessions do
          resources :auditions, only: [ :show ], to: "audition_sessions#show"
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
          get    "prepare",           to: "auditions#prepare",                   as: "prepare"
          get    "publicize",         to: "auditions#publicize",                 as: "publicize"
          get    "review",            to: "auditions#review",                    as: "review"
          patch  "finalize_invitations", to: "auditions#finalize_invitations",  as: "finalize_invitations"
          get    "run",               to: "auditions#run",                       as: "run"
          get    "casting",           to: "auditions#casting",                   as: "casting"
          get    "casting/select",    to: "auditions#casting_select",           as: "casting_select"
          post   "add_to_cast_assignment", to: "auditions#add_to_cast_assignment", as: "add_to_cast_assignment"
          post   "remove_from_cast_assignment", to: "auditions#remove_from_cast_assignment", as: "remove_from_cast_assignment"
          post   "finalize_and_notify", to: "auditions#finalize_and_notify",    as: "finalize_and_notify"
          post   "finalize_and_notify_invitations", to: "auditions#finalize_and_notify_invitations", as: "finalize_and_notify_invitations"
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

      get "/audition_sessions/summary", to: "audition_sessions#summary", as: "audition_session_summary"

      resources :cast_assignment_stages, only: [ :create, :update, :destroy ]
      resources :email_groups, only: [ :create, :update, :destroy ]
      resources :audition_email_assignments, only: [ :create, :update, :destroy ]
      resources :auditions
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

  # Profile routes (top-level)
  get    "/profile",         to: "profile#index",   as: "profile"
  get    "/profile/welcome", to: "profile#welcome", as: "profile_welcome"
  post   "/profile/dismiss_welcome", to: "profile#dismiss_welcome", as: "dismiss_profile_welcome"
  post   "/profile/mark_welcomed", to: "profile#mark_welcomed", as: "mark_profile_welcomed"
  patch  "/profile",         to: "profile#update",  as: "update_profile"
  patch  "/profile/visibility", to: "profile#update_visibility", as: "update_profile_visibility"
  patch  "/profile/headshots/:id/set_primary", to: "profile#set_primary_headshot", as: "set_primary_headshot"
  get    "/profile/public",  to: "profile#public",  as: "profile_public"
  get    "/profile/change-url", to: "profile#change_url", as: "change_url_profile"
  post   "/profile/check-url-availability", to: "profile#check_url_availability", as: "check_url_availability_profile"
  patch  "/profile/update-url", to: "profile#update_url", as: "update_url_profile"
  get    "/profile/search_groups", to: "profile#search_groups", as: "search_groups_profile"
  post   "/profile/join_group", to: "profile#join_group", as: "join_group_profile"
  delete "/profile/leave_group/:id", to: "profile#leave_group", as: "leave_group_profile"
  get    "/profile/change-email", to: "profile#change_email", as: "change_email_profile"
  patch  "/profile/change-email", to: "profile#update_email", as: "update_email_profile"

  # Groups routes (top-level, use profile layout)
  get    "/groups",                   to: "groups#index",      as: "groups"
  get    "/groups/new",               to: "groups#new",        as: "new_group"
  post   "/groups",                   to: "groups#create",     as: "create_group"
  patch  "/groups/:group_id/headshots/:id/set_primary", to: "groups#set_primary_headshot", as: "set_primary_group_headshot"
  post   "/groups/:id/check-url-availability", to: "groups#check_url_availability", as: "check_url_availability_group"
  patch  "/groups/:id/update-url", to: "groups#update_url", as: "update_url_group"
  patch  "/groups/:id/visibility", to: "groups#update_visibility", as: "update_group_visibility"
  get    "/groups/:id",               to: "groups#edit",       as: "edit_group"
  get    "/groups/:id/settings",      to: "groups#settings",   as: "settings_group"
  patch  "/groups/:id",               to: "groups#update",     as: "update_group"
  patch  "/groups/:id/update_member_role", to: "groups#update_member_role", as: "update_member_role_group"
  delete "/groups/:id/remove_member", to: "groups#remove_member", as: "remove_member_group"
  patch  "/groups/:id/update_member_notifications", to: "groups#update_member_notifications", as: "update_member_notifications_group"
  patch  "/groups/:id/archive",       to: "groups#archive",    as: "archive_group"
  patch  "/groups/:id/unarchive",     to: "groups#unarchive",  as: "unarchive_group"

  # Group invitations
  post "/groups/:group_id/invitations", to: "group_invitations#create", as: "group_invitations"
  delete "/groups/:group_id/invitations/:id", to: "group_invitations#revoke", as: "revoke_group_invitation"
  get "/group_invitations/:token/accept", to: "group_invitations#accept", as: "accept_group_invitation"
  post "/group_invitations/:token/accept", to: "group_invitations#do_accept", as: "do_accept_group_invitation"

  # Public profiles (must be last to catch any remaining paths)
  get "/:public_key/shoutouts", to: "public_profiles#shoutouts", as: "public_profile_shoutouts", constraints: { public_key: /[a-z0-9][a-z0-9\-]{2,29}/ }
  get "/:public_key", to: "public_profiles#show", as: "public_profile", constraints: { public_key: /[a-z0-9][a-z0-9\-]{2,29}/ }
end
