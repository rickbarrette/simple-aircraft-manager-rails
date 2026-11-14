class NotesController < ApplicationController
  include AircraftScoped
  before_action :require_owner!, only: %i[edit update destroy]
  before_action :set_note, only: %i[edit update destroy]

  def index
    @notes = @aircraft.notes.recent_first.includes(:user)
  end

  # Rendered Markdown for the editor's Preview tab.
  def preview
    render html: helpers.markdown(params[:text].to_s.first(50_000)).presence || helpers.tag.p("Nothing to preview.", class: "hint")
  end

  def new
    @note = @aircraft.notes.new
  end

  def create
    @note = @aircraft.notes.new(note_params.merge(user: current_user))
    if @note.save
      log_event("note", t("flash.notes.note_added_2"))
      redirect_to aircraft_notes_path(@aircraft), notice: t("flash.notes.note_added")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @note.update(note_params.merge(edited_at: Time.current))
      log_event("note", t("flash.notes.note_updated_2"))
      redirect_to aircraft_notes_path(@aircraft), notice: t("flash.notes.note_updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @note.destroy!
    log_event("note", t("flash.notes.note_deleted_2"))
    redirect_to aircraft_notes_path(@aircraft), notice: t("flash.notes.note_deleted")
  end

  private

  def set_note = @note = @aircraft.notes.find(params[:id])
  def note_params = params.require(:aircraft_note).permit(:text, :public)
end
