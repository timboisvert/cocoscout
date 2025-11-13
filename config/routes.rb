Rails.application.routes.draw do
  root "home#index"

  # Utility
  get "/up", to: proc { [ 200, {}, [ "OK" ] ] }

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
  end

  # Respond to an audition request
  get "/a/:token", to: "my/submit_audition_request#entry", as: "submit_audition_request"

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
    get   "/profile",                       to: "profile#index",            as: "profile"
    get   "/profile/edit",                  to: "profile#edit",             as: "edit_profile"
    patch "/profile/edit",                  to: "profile#update",           as: "update_profile"

    scope "/auditions/:token" do
      get "/", to: redirect { |params, _req| "/a/#{params[:token]}" }
      get "/form", to: "submit_audition_request#form", as: "submit_audition_request_form"
      post "/form", to: "submit_audition_request#submitform", as: "submit_submit_audition_request_form"
      get "/success", to: "submit_audition_request#success", as: "submit_audition_request_success"
      get "/inactive", to: "submit_audition_request#inactive", as: "submit_audition_request_inactive"
    end
  end

  # Management interface
  namespace :manage do
    get "/", to: "manage#index"

    resources :organizations do
      collection do
        get :select
        post :set_current
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

    resources :people do
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
          get :edit_logo
          patch :update_logo
        end
      end

      resources :shows do
        collection do
          get :calendar
        end
        member do
          get   :cast
          get   :cancel, action: :cancel
          patch :cancel_show
          delete :delete_show
          patch :uncancel
        end
      end
      resources :casts do
        collection do
          get :search_people
        end
        member do
          # These two are only used when dragging and dropping on the cast members list
          post :add_person
          post :remove_person
        end
      end

      resources :roles do
        collection do
          post :reorder
        end
      end

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

      get "/audition_sessions/summary", to: "audition_sessions#summary", as: "audition_session_summary"

      resources :cast_assignment_stages, only: [ :create, :update, :destroy ]
      resources :email_groups, only: [ :create, :destroy ]
      resources :audition_email_assignments, only: [ :create, :update, :destroy ]
      resources :auditions
    end

    # Used for adding people and removing them from an audition session
    post "/auditions/add_to_session",       to: "auditions#add_to_session"
    post "/auditions/remove_from_session",  to: "auditions#remove_from_session"
    post "/auditions/move_to_session",      to: "auditions#move_to_session"

    # Used for adding people and removing them from a cast
    post "/shows/:id/assign_person_to_role",    to: "shows#assign_person_to_role"
    post "/shows/:id/remove_person_from_role",  to: "shows#remove_person_from_role"
  end

  # Junkers
  get "/wp-admin/*", to: proc { [ 200, {}, [ "" ] ] }
  get "/wp-include/*", to: proc { [ 200, {}, [ "" ] ] }
  get "/.well-known/appspecific/*path", to: proc { [ 204, {}, [] ] }
end
