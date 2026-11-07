# The electronic signature and recordkeeping procedures document
# (AC 120-78B 2.2.11 / 3.2.8): the owner fills in what the app can't know,
# reviews the generated draft, and adopts it as a numbered revision.
class Admin::ProceduresController < ApplicationController
  before_action :require_admin!

  def show
    @policy = RecordkeepingPolicy.current
    @revisions = ProceduresRevision.latest_first.includes(:adopted_by)
  end

  def update
    @policy = RecordkeepingPolicy.current
    if @policy.update(params.require(:recordkeeping_policy).permit(:operator_name, :responsible_name, :responsible_title, :hosting_description,
                                                                  :offsite_backup_description, :audit_interval_months, :audit_sample_size,
                                                                  :additional_procedures))
      redirect_to admin_procedures_path, notice: "Saved. Review the draft and adopt it as a new revision when it's right."
    else
      @revisions = ProceduresRevision.latest_first
      render :show, status: :unprocessable_entity
    end
  end

  # The current draft, printable.
  def draft
    render html: draft_html.html_safe, layout: "report"
  end

  def adopt
    policy = RecordkeepingPolicy.current
    return redirect_to(admin_procedures_path, alert: "Fill in the operator, responsible person, hosting and off-site backup (or connect Google Drive) first.") unless policy.complete?
    number = (ProceduresRevision.maximum(:number) || 0) + 1
    revision = ProceduresRevision.create!(number: number, adopted_by: current_user, adopted_at: Time.current,
                                          summary: params[:summary].to_s.strip.first(500).presence || "Revision #{number}",
                                          content: draft_html(number: number, summary: params[:summary].to_s.strip.first(500)))
    redirect_to admin_procedures_path, notice: "Revision #{revision.number} adopted. Print it or keep the PDF with your records."
  end

  def revision
    @revision = ProceduresRevision.find(params[:id])
    render html: @revision.content.html_safe, layout: "report"
  end

  private

  def draft_html(number: nil, summary: nil)
    render_to_string(partial: "admin/procedures/document",
                     locals: { policy: RecordkeepingPolicy.current, number: number || "#{(ProceduresRevision.maximum(:number) || 0) + 1} (draft)",
                               adopted_at: number ? Time.current : nil, adopted_by: number ? current_user : nil,
                               revisions: ProceduresRevision.latest_first.to_a, summary: summary })
  end
end
