Rails.application.routes.draw do
  # Signed-in users only, with the upload rules checked before any bytes are sent
  # (overrides Active Storage's open endpoint at the same path).
  post "rails/active_storage/direct_uploads", to: "direct_uploads#create"

  resource :session
  resources :sign_in_links, path: "session/link", param: :token, only: %i[new create show] do
    post :consume, on: :member
  end
  # Single sign-on: POST /auth/oidc (handled by OmniAuth) comes back here.
  match "auth/:provider/callback", to: "sso#callback", via: %i[get post], as: :sso_callback
  get "auth/failure", to: "sso#failure"
  delete "profile/sso", to: "sso#destroy", as: :sso_link
  delete "profile/sessions", to: "profiles#sign_out_others", as: :other_sessions
  resources :passwords, param: :token
  resource :setup, only: %i[new create], controller: "setup"
  resource :profile, only: %i[edit update]
  resource :air_trail_connection, path: "profile/airtrail", only: %i[show create update destroy] do
    post :test
    post :sync
    post :map_airport
  end

  resources :aircraft_imports, path: "imports", only: %i[new create show]
  resources :aircraft do
    member do
      patch :hours, action: :update_hours
    end

    resources :components do
      member { post :reset_service }
    end
    resources :squawks, except: :show do
      member do
        patch :resolve
        patch :reopen
      end
    end
    resources :notes, except: :show do
      post :preview, on: :collection
    end
    resources :flight_logs, only: %i[index new create show destroy] do
      member do
        get :engine_data, action: :engine_data_series
        patch :engine_data, action: :attach_engine_data
        delete :engine_data, action: :remove_engine_data
      end
    end
    resource :air_trail_export, path: "airtrail_export", only: %i[new create]
    resource :airport_codes, only: %i[show update]
    resource :flight_import, only: %i[new create show] do
      post :confirm
    end
    resources :consumable_records, path: "consumables", except: :show
    resources :oil_analyses, path: "oil_analysis" do
      collection { post :import }
    end
    resources :logbook_imports, path: "logbook/import", only: %i[new create show]
    resources :logbook_entries
    resources :documents do
      collection do
        get :bulk, action: :bulk_new, as: :new_bulk
        post :bulk, action: :bulk_create
      end
    end
    resources :document_collections, except: %i[index show]
    resources :inspections, only: :index
    resources :inspection_types, except: %i[index show]
    resources :inspection_records, except: %i[index show]
    resources :airworthiness_directives, path: "ads", except: :show do
      collection { post :attach }
    end
    resources :ad_compliances, except: %i[index show]
    resource :ad_import, only: %i[new create show] do
      post :confirm
    end
    resources :major_records
    resources :aircraft_roles, path: "access", only: %i[index create update destroy]
    resources :share_tokens, only: %i[create destroy]
    resource :export, controller: "aircraft_exports", only: :show
    resource :report, controller: "maintenance_reports", only: :show
    resources :events, only: :index
  end

  get "airports/search", to: "airports#search", as: :airport_search

  # Public read-only share links (no login).
  get "shared/:token", to: "shared#show", as: :shared
  get "shared/:token/report", to: "shared#report", as: :shared_report

  namespace :admin do
    get "about", to: "about#show"
    resource :settings, only: %i[edit update]
    post "about/test_email", to: "about#test_email", as: :test_email
    resources :users, except: :show
    resources :component_types, except: :show
    resources :airports, except: :show do
      collection { post :refresh }
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  root "aircraft#index"
end
