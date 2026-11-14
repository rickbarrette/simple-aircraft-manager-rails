# Upload a .sam.zip (from this app or the original Simple Aircraft Manager) to
# create an aircraft with all its records. The archive is checked right away;
# the import itself runs in the background (AircraftImportJob).
class AircraftImportsController < ApplicationController
  before_action :set_import, only: :show

  def new; end

  def create
    file = params[:archive]
    return redirect_to(new_aircraft_import_path, alert: t("flash.aircraft_imports.choose_a_sam_zip")) if file.blank?

    preview = AircraftArchive::Importer.check(file.tempfile.path)
    tail = params[:tail_number].to_s.strip.upcase.presence || preview.tail_number.to_s.upcase
    if Aircraft.where("UPPER(tail_number) = ?", tail).exists?
      @preview = preview
      @conflict = tail
      flash.now[:alert] = t("flash.aircraft_imports.an_aircraft_already_exists", tail: tail)
      return render :new, status: :unprocessable_entity
    end

    import = AircraftImport.create!(user: current_user, filename: file.original_filename, tail_number: tail, source: preview.source)
    import.archive.attach(io: file.tempfile.tap(&:rewind), filename: file.original_filename.presence || "archive.sam.zip", content_type: "application/zip")
    AircraftImportJob.perform_later(import.id)
    redirect_to aircraft_import_path(import)
  rescue AircraftArchive::Error => e
    redirect_to new_aircraft_import_path, alert: t("flash.aircraft_imports.that_archive_can_t", message: e.message)
  end

  def show; end

  private

  # Users see their own imports; admins see all.
  def set_import
    scope = current_user.admin? ? AircraftImport.all : AircraftImport.where(user: current_user)
    @import = scope.find(params[:id])
  end
end
