module Api
  module V1
    # What this token is and who it's acting as: a quick check for a new integration.
    class MeController < BaseController
      def show
        render json: { data: {
          token: { name: api_token.name, kind: api_token.kind, hint: api_token.token_hint, scopes: api_token.scopes,
                   aircraft_ids: (api_token.aircraft_ids if api_token.integration?) }.compact,
          acting_as: acting_user && { id: acting_user.id, name: acting_user.display_name, email: acting_user.email_address },
          aircraft_ids: aircraft_scope.ids,
          api_version: "v1", app_version: Rails.root.join("VERSION").read.strip
        } }
      end
    end
  end
end
