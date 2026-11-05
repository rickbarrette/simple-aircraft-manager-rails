# Owner-only import of ADs from an FAA DRS export: upload → preview → confirm.
class AdImportsController < ApplicationController
  include AircraftScoped
  include StoredUpload
  before_action :require_owner!

  def new; end

  def create
    token, error = store_upload(params[:file])
    return redirect_to_upload(error) if error
    redirect_to aircraft_ad_import_path(@aircraft, token: token, filename: params[:file].original_filename)
  end

  def show
    @token = params[:token].to_s
    return redirect_to_upload("Upload expired. Please upload the file again.") unless stored_file?(@token)
    @filename = params[:filename].to_s
    @import = AdImport.new(@aircraft, path: stored_path(@token), filename: @filename)
    @import.rows
  rescue AdImport::Error => e
    redirect_to_upload(e.message)
  end

  def confirm
    token = params[:token].to_s
    return redirect_to_upload("Upload expired. Please upload the file again.") unless stored_file?(token)
    import = AdImport.new(@aircraft, path: stored_path(token), filename: params[:filename])
    # Only AD numbers present in the uploaded file; values are checked against AdImport::ACTIONS.
    decisions = params.fetch(:decisions, {}).permit(*import.rows.map(&:number)).to_h
    result = import.import!(decisions: decisions, user: current_user)
    discard_upload(token)
    redirect_to aircraft_airworthiness_directives_path(@aircraft),
                notice: "Imported #{result[:tracked]} ADs to track and #{result[:not_applicable]} marked N/A; " \
                        "#{result[:updated]} existing ADs updated, #{result[:skipped]} skipped."
  rescue AdImport::Error => e
    redirect_to_upload(e.message)
  end

  private

  def redirect_to_upload(message)
    redirect_to new_aircraft_ad_import_path(@aircraft), alert: message
  end
end
