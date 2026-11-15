module Api
  module V1
    # Draft logbook entries for one visit (docs/api.md, "Draft entries"). The
    # work items become one unsigned entry per logbook, signed in the app; the
    # squawks they resolve and inspections they complete are held until every
    # entry is signed. Like writing entries in the app, it's for the
    # aircraft's owners.
    class DraftBatchesController < BaseController
      before_action -> { require_scope!(:read) }, only: %i[index show lookup]
      before_action -> { require_scope!("drafts:write") }, :require_person!, only: %i[create destroy]

      def index
        scope = find_aircraft.draft_batches.includes(entries: :signature)
        scope = scope.where(status: params[:status]) if params[:status].present?
        render_page(scope) { ApiPresenter.draft_batch(_1) }
      end

      def lookup
        scope = DraftBatch.where(aircraft: aircraft_scope, external_ref: params.require(:external_ref)).includes(entries: :signature)
        render json: { data: scope.map { ApiPresenter.draft_batch(_1) } }
      end

      def show
        render json: { data: ApiPresenter.draft_batch(find_batch) }
      end

      # POST /aircraft/:aircraft_id/draft_batches
      def create
        @aircraft = find_aircraft
        return not_permitted(:write_logbook) unless can?(:write_logbook, @aircraft)

        input = params.require(:draft_batch)
        items = Array(input[:items]).map { _1.permit(:log, :text, :external_ref, resolves_squawks: []) }
        errors = check(input, items)
        return render_error(:unprocessable_entity, "invalid", errors.values.flatten.to_sentence, fields: errors) if errors.any?

        invitations = {}
        batch = DraftBatch.transaction do
          b = @aircraft.draft_batches.create!(api_token: api_token, created_by: acting_user, external_ref: input[:external_ref],
                                              signer_email: signer_email(input), held: held(input, items))
          items.group_by { _1[:log] }.each do |log, group|
            entry = b.entries.create!(aircraft: @aircraft, log_type: log, date: input[:date], text: group.map { _1[:text].to_s.strip }.join("\n\n"),
                                      entry_type: inspection_logs(input, items).include?(log) ? "INSPECTION" : "MAINTENANCE",
                                      inspection_result: inspection_result_for(input, items, log),
                                      aircraft_hours_at_entry: input[:aircraft_hours].presence, external_ref: group.filter_map { _1[:external_ref] }.join(",").presence)
            invitations[entry.id] = invite(entry, b.signer_email, send: input.dig(:signer, :send_email).to_s == "true") if b.signer_email
          end
          b
        end
        @aircraft.log_event!("logbook", I18n.t("api.draft_batches.sent", count: batch.entries.size, name: api_token.name), notes: batch.external_ref)
        render json: { data: ApiPresenter.draft_batch(batch.reload, invitations: invitations) }, status: :created
      end

      # DELETE /draft_batches/:id: withdraw it while nothing in it is signed.
      def destroy
        batch = find_batch
        return not_permitted(:write_logbook) unless can?(:write_logbook, batch.aircraft)
        unless batch.awaiting? && batch.entries.none?(&:signed?)
          return render_error(:conflict, "signed", "Part of this draft is signed (or it's no longer awaiting signature); correct it in the app instead.")
        end
        batch.withdraw!
        render json: { data: ApiPresenter.draft_batch(batch.reload) }
      end

      private

      def find_batch = DraftBatch.where(aircraft: aircraft_scope).includes(entries: :signature).find(params[:id])

      def check(input, items)
        errors = Hash.new { |h, k| h[k] = [] }
        errors[:items] << "at least one item is needed" if items.empty?
        items.each_with_index do |item, i|
          errors[:"items.#{i}.log"] << "must be one of #{LogbookEntry::LOG_TYPES.keys.join(', ')}" unless LogbookEntry::LOG_TYPES.key?(item[:log])
          errors[:"items.#{i}.text"] << "can't be blank" if item[:text].blank?
        end
        errors[:date] << "must be a date (YYYY-MM-DD)" unless (Date.iso8601(input[:date].to_s) rescue nil)
        errors[:aircraft_hours] << "must be a number" if input[:aircraft_hours].present? && !input[:aircraft_hours].to_s.match?(/\A\d+(\.\d+)?\z/)
        squawk_ids = items.flat_map { Array(_1[:resolves_squawks]) }.map(&:to_i)
        missing = squawk_ids - @aircraft.squawks.active.where(id: squawk_ids).ids
        errors[:resolves_squawks] << "no open squawk #{missing.join(', ')} on this aircraft" if missing.any?
        Array(input[:completes_inspections]).each_with_index do |c, i|
          id = c.respond_to?(:[]) ? c[:inspection_type_id].to_i : 0
          errors[:"completes_inspections.#{i}"] << "no inspection #{id} applies to this aircraft" unless @aircraft.applicable_inspection_types.exists?(id: id)
          log = inspection_log(c, items)
          errors[:"completes_inspections.#{i}.log"] << "must be the log of one of the items" unless items.any? { _1[:log] == log }
          unless LogbookEntry::INSPECTION_RESULTS.key?(c.respond_to?(:[]) ? c[:result].to_s : "")
            errors[:"completes_inspections.#{i}.result"] << "must be #{LogbookEntry::INSPECTION_RESULTS.keys.join(' or ')}"
          end
        end
        Array(input[:completes_inspections]).group_by { inspection_log(_1, items) }.each do |log, group|
          errors[:completes_inspections] << "inspections in the #{log} log need the same result (one entry)" if group.map { _1[:result].to_s }.uniq.size > 1
        end
        errors[:aircraft_hours] << "is needed to record an inspection" if Array(input[:completes_inspections]).any? && input[:aircraft_hours].blank?
        email = input.dig(:signer, :email).to_s.strip
        errors[:"signer.email"] << "isn't an email address" if email.present? && !email.match?(URI::MailTo::EMAIL_REGEXP)
        errors[:"signer.send_email"] << "needs email set up on the server" if input.dig(:signer, :send_email).to_s == "true" && !MailSettings.configured?
        errors
      end

      # The inspection goes in the logbook named for it, else the airframe
      # log if there's an item for it, else the first item's.
      def inspection_log(c, items)
        c[:log].presence || (items.any? { _1[:log] == "AC" } ? "AC" : items.first&.dig(:log))
      end

      def inspection_logs(input, items) = Array(input[:completes_inspections]).map { inspection_log(_1, items) }

      # approved | discrepancies, for the entry in that log that records inspections.
      def inspection_result_for(input, items, log)
        Array(input[:completes_inspections]).find { inspection_log(_1, items) == log }&.dig(:result)
      end

      def held(input, items)
        { "squawks" => items.flat_map { |it| Array(it[:resolves_squawks]).map { |id| { "id" => id.to_i, "log" => it[:log] } } }.uniq { _1["id"] },
          "inspections" => Array(input[:completes_inspections]).map { { "id" => _1[:inspection_type_id].to_i, "log" => inspection_log(_1, items) } } }
      end

      def signer_email(input) = input.dig(:signer, :email).to_s.strip.downcase.presence

      # A link for the signer to sign this entry with their own account,
      # returned to the caller to pass on; emailed too when asked.
      def invite(entry, email, send: false)
        invitation = entry.signing_invitations.create!(email: email, invited_by: acting_user)
        SigningInvitationMailer.invite(invitation, invitation.token).deliver_later if send
        invitation.token
      end
    end
  end
end
