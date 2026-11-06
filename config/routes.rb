Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resource :setup, only: %i[new create], controller: "setup"
  resource :profile, only: %i[edit update]
  resource :air_trail_connection, path: "profile/airtrail", only: %i[show create update destroy] do
    post :test
    post :sync
    post :map_airport
  end

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
    resources :notes, except: :show
    resources :flight_logs, only: %i[index new create show destroy] do
      member do
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
    resources :logbook_entries
    resources :documents
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
    resources :events, only: :index
  end

  get "airports/search", to: "airports#search", as: :airport_search

  # Public read-only share links (no login).
  get "shared/:token", to: "shared#show", as: :shared

  namespace :admin do
    resources :users, except: :show
    resources :component_types, except: :show
    resources :airports, except: :show do
      collection { post :refresh }
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
  root "aircraft#index"
end
