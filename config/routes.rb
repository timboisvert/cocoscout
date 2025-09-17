Rails.application.routes.draw do
  root "home#index"

  # Utility
  get "/up", to: proc { [ 200, {}, [ "OK" ] ] }

  # Landing page
  get "home/index"
  post "/notify_me", to: "home#notify_me", as: "notify_me"
  get "/notify_me/success", to: "home#notify_me_success", as: "notify_me_success"

  # Public-facing routes
  get "/audition/:hex_code", to: "respond_to_call_to_audition#new", as: "respond_to_call_to_audition"
  post "/audition/:hex_code", to: "respond_to_call_to_audition#create", as: "handle_respond_to_call_to_audition"
  get "/audition/:hex_code/success", to: "respond_to_call_to_audition#success", as: "respond_to_call_to_audition_success"
  get "/audition/:hex_code/inactive", to: "respond_to_call_to_audition#inactive", as: "respond_to_call_to_audition_inactive"

  # Authentication
  get "/signup", to: "users#signup", as: "signup"
  post "/signup", to: "users#create", as: "create_user"
  resource :session
  resources :passwords, param: :token

  scope "/app" do
    get "/", to: "dashboard#index", as: "dashboard"

    resources :production_companies do
      collection do
        get :select
        post :set_current
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

    resources :productions do
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
        resources :audition_requests
        post "audition_requests/:id/set_status/:status", to: "audition_requests#set_status", as: "audition_request_set_status"
      end
      get "call_to_auditions/:id/preview", to: "call_to_auditions#preview", as: "call_to_audition_preview"

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
  get "/wp-admin/*", to: proc { [ 200, {}, [ "" ] ] }
end
