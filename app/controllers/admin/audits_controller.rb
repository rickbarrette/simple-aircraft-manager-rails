class Admin::AuditsController < ApplicationController
  before_action :require_admin!

  def index
    @audits = AuditRun.latest_first.includes(:performed_by)
  end

  def new
    @audit = RecordsAudit.new
  end

  def create
    answers = params.fetch(:answers, {}).permit(RecordsAudit::MANUAL.keys.index_with { %i[passed note] }).to_h
    run = RecordsAudit.new.record!(user: current_user, answers: answers, notes: params[:notes], sample_ids: Array(params[:sample_ids]).map(&:to_i))
    redirect_to admin_audit_path(run), notice: run.passed ? t("flash.admin_audits.passed") : t("flash.admin_audits.not_passed")
  end

  def show
    @audit = AuditRun.find(params[:id])
  end
end
