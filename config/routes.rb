Rails.application.routes.draw do
  root "home#index"

  # Utility
  get "/up", to: proc { [ 200, {}, [ "OK" ] ] }

  # Landing page
  get "home/index"
  post "/notify_me", to: "home#notify_me", as: "notify_me"
  get "/notify_me/success", to: "home#notify_me_success", as: "notify_me_success"

  # Authentication
  get   "/signup",    to: "auth#signup",          as: "signup"
  post  "/signup",    to: "auth#handle_signup",   as: "handle_signup"
  get   "/signin",    to: "auth#signin",          as: "signin"
  post  "/signin",    to: "auth#handle_signin",   as: "handle_signin"
  get   "/signout",   to: "auth#signout",         as: "signout"
  get   "/password",  to: "auth#password",        as: "password"
  post  "/password",  to: "auth#handle_password", as: "handle_password"

  # God mode
  scope "/god_mode" do
    get  "/",                   to: "god_mode#index",               as: "god_mode"
    post "/impersonate",        to: "god_mode#impersonate",         as: "impersonate_user"
    post "/stop_impersonating", to: "god_mode#stop_impersonating",  as: "stop_impersonating_user"
  end

  # Respond to an audition request
  get "/a/:token", to: "my/respond_to_call_to_audition#entry", as: "respond_to_call_to_audition"

  # Talent-facing interface
  namespace :my do
    get   "/",                              to: "dashboard#index",          as: "dashboard"
    get   "/shows",                         to: "shows#index",              as: "shows"
    get   "/shows/:production_id",          to: "shows#production",         as: "production"
    get   "/shows/:production_id/:show_id", to: "shows#show",               as: "show"
    get   "/auditions",                     to: "auditions#index",          as: "auditions"
    get   "/audition_requests",             to: "audition_requests#index",  as: "audition_requests"
    get   "/profile",                       to: "profile#index",            as: "profile"
    get   "/profile/edit",                  to: "profile#edit",             as: "edit_profile"
    patch "/profile/edit",                  to: "profile#update",           as: "update_profile"

    scope "/auditions/:token" do
      get "/", to: redirect { |params, _req| "/a/#{params[:token]}" }
      get "/form", to: "respond_to_call_to_audition#form", as: "respond_to_call_to_audition_form"
      post "/form", to: "respond_to_call_to_audition#submitform", as: "submit_respond_to_call_to_audition_form"
      get "/success", to: "respond_to_call_to_audition#success", as: "respond_to_call_to_audition_success"
      get "/inactive", to: "respond_to_call_to_audition#inactive", as: "respond_to_call_to_audition_inactive"
    end
  end

  # Management interface
  namespace :manage do
    get "/", to: "manage#index"

    resources :production_companies do
      collection do
        get :select
        post :set_current
      end
    end

    resources :team, only: [ :index ] do
      collection do
        post :invite
        patch :update_role
        delete :revoke_invite
        delete :remove_member
      end
    end

    resources :team_invitations do
      collection do
        get "accept/:token", to: "team_invitations#accept", as: :accept
        post "accept/:token", to: "team_invitations#do_accept", as: :do_accept
      end
    end

    resources :people do
      collection do
        get :search
      end
      member do
        # Used when adding a person to a cast from a person (or person-like) page
        post :add_to_cast
        post :remove_from_cast
      end
    end

    resources :locations

    resources :productions do
      resources :posters, except: :index
      resources :shows
      resources :casts do
        member do
          # These two are only used when dragging and dropping on the cast members list
          post :add_person
          post :remove_person
        end
      end

      resources :roles

      resources :call_to_auditions do
        resources :questions
        resources :audition_requests do
          member do
            get   "edit_answers",       to: "audition_requests#edit_answers", as: "edit_answers"
            get   "edit_video",         to: "audition_requests#edit_video",   as: "edit_video"
            post  "set_status/:status", to: "audition_requests#set_status",   as: "set_status"
          end
        end
        member do
          get  "form",      to: "call_to_auditions#form",     as: "form"
          get  "preview",   to: "call_to_auditions#preview",  as: "preview"
        end
      end

      get "/audition_sessions/summary", to: "audition_sessions#summary", as: "audition_session_summary"
      resources :audition_sessions do
        get "/auditions/:id", to: "audition_sessions#show", as: "audition"
      end

      resources :auditions
    end

    # Used for adding people and removing them from an audition session
    post "/auditions/add_to_session", to: "auditions#add_to_session"
    post "/auditions/remove_from_session", to: "auditions#remove_from_session"

    # Used for adding people and removing them from a cast
    post "/shows/:id/assign_person_to_role", to: "shows#assign_person_to_role"
    post "/shows/:id/remove_person_from_role", to: "shows#remove_person_from_role"
  end

  # Junkers
  get "/wp-admin/*", to: proc { [ 200, {}, [ "" ] ] }
  get "/wp-include/*", to: proc { [ 200, {}, [ "" ] ] }
end
