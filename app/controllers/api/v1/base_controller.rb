# The REST API, version 1 (docs/api.md). JSON in and out; a token in
# "Authorization: Bearer sam_…" instead of a browser session, so no cookies
# and no CSRF tokens.
#
# A personal token acts as its owner. An integration token acts for the
# person named in "SAM-On-Behalf-Of: <email>" (required for writes), and
# reaches only its aircraft that person can also see.
module Api
  module V1
    class BaseController < ActionController::API
      include RejectsNullBytes

      MAX_PAGE = 200

      before_action :authenticate
      rate_limit to: 600, within: 1.minute, by: -> { @api_token&.id || request.remote_ip },
                 with: -> { render_error(:too_many_requests, "rate_limited", "Too many requests; slow down.") }
      around_action :idempotent, if: -> { request.post? || request.patch? || request.delete? }

      rescue_from ActiveRecord::RecordNotFound do
        render_error(:not_found, "not_found", "Not found, or not available to this token.")
      end
      rescue_from ActionController::ParameterMissing, ActionDispatch::Http::Parameters::ParseError do |e|
        render_error(:bad_request, "bad_request", e.message.truncate(200))
      end
      rescue_from ActiveRecord::RecordInvalid do |e|
        render_invalid(e.record)
      end
      rescue_from ActiveSupport::MessageVerifier::InvalidSignature, ActiveModel::RangeError,
                  ActiveRecord::NotNullViolation, ActiveRecord::InvalidForeignKey do
        render_error(:unprocessable_entity, "invalid", "Some values couldn't be saved.")
      end

      private

      attr_reader :api_token

      def acting_user = Current.api_user

      def authenticate
        token = request.authorization.to_s[/\ABearer\s+(\S+)\z/i, 1]
        @api_token = ApiToken.authenticate(token)
        return render_error(:unauthorized, "unauthorized", "A valid API token is required.") unless @api_token

        Current.api_token = @api_token
        Current.ip_address = request.remote_ip
        Current.api_user = @api_token.personal? ? @api_token.user : on_behalf_of
        @api_token.used!(request.remote_ip)
      end

      # The person an integration is acting for, if it named one.
      def on_behalf_of
        email = request.headers["SAM-On-Behalf-Of"].to_s.strip.downcase.presence or return
        User.active.find_by(email_address: email) ||
          render_error(:unprocessable_entity, "unknown_user", "SAM-On-Behalf-Of doesn't match an active user.")
      end

      def require_scope!(scope)
        return if api_token.allows?(scope)
        render_error(:forbidden, "missing_scope", "This token doesn't have the #{scope} scope.")
      end

      # Writes always name a person, so the record history shows who.
      def require_person!
        return if acting_user
        render_error(:unprocessable_entity, "on_behalf_of_required", "Writes with an integration token need SAM-On-Behalf-Of.")
      end

      def aircraft_scope = api_token.aircraft_scope(acting_user)

      def find_aircraft(id = params[:aircraft_id]) = aircraft_scope.find(id)

      def role_on(aircraft) = acting_user&.role_for(aircraft)
      def owner_of?(aircraft) = role_on(aircraft).in?(%w[admin owner])

      # ?limit= (1–200, default 50), ?after=<id> to continue, ?updated_since=<ISO time>.
      def paginate(scope)
        limit = params.fetch(:limit, 50).to_i.clamp(1, MAX_PAGE)
        scope = scope.where(scope.arel_table[:id].gt(params[:after].to_i)) if params[:after].present?
        if params[:updated_since].present?
          since = Time.iso8601(params[:updated_since].to_s) rescue (raise ActionController::BadRequest, "updated_since must be an ISO 8601 time")
          scope = scope.where(scope.arel_table[:updated_at].gteq(since))
        end
        records = scope.reorder(:id).limit(limit + 1).to_a
        more = records.size > limit
        records = records.first(limit)
        [ records, (records.last.id if more) ]
      end

      def render_page(scope, &present)
        records, next_after = paginate(scope)
        render json: { data: records.map(&present), next_after: next_after }
      end

      def render_error(status, code, message, fields: nil)
        render json: { error: { code: code, message: message, fields: fields }.compact }, status: status
      end

      def render_invalid(record)
        render_error(:unprocessable_entity, "invalid", record.errors.full_messages.to_sentence, fields: record.errors.to_hash)
      end

      # The same Idempotency-Key again (a retry) gets the first answer; the
      # same key with a different request is a conflict.
      def idempotent
        key = request.headers["Idempotency-Key"].to_s.strip
        return yield if key.empty? || api_token.nil?
        return render_error(:bad_request, "bad_request", "Idempotency-Key is too long.") if key.length > 100

        digest = OpenSSL::Digest::SHA256.hexdigest([ request.method, request.path, request.raw_post ].join("\n"))
        if (seen = api_token.idempotency_keys.find_by(key: key))
          return render_error(:conflict, "idempotency_conflict", "This Idempotency-Key was used for a different request.") if seen.request_digest != digest
          response.headers["Idempotent-Replay"] = "true"
          return render(json: seen.response_body, status: seen.response_status)
        end
        yield
        return if response.status >= 500
        api_token.idempotency_keys.create(key: key, request_digest: digest, response_status: response.status,
                                          response_body: response.body, created_at: Time.current)
      end
    end
  end
end
