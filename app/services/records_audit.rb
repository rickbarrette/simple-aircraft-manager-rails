# The QC audit checklist (AC 120-78B 3.2.8.5): items the app checks itself,
# and items the auditor confirms (restore test, comparing a sample of entries
# with their source documents, reviewing users).
class RecordsAudit
  Item = Data.define(:key, :title, :auto, :passed, :detail)

  MANUAL = LabelSet.new("records_audit.manual", %w[restore_test sample users legacy])

  def initialize(since: AuditRun.latest&.performed_at)
    @since = since
    @policy = RecordkeepingPolicy.current
  end

  def auto_items
    check = IntegrityCheck.latest
    backup = BackupRun.latest
    revision = ProceduresRevision.current
    expired = UserCertificate.joins(:user).merge(User.active).where(expires_on: ...Date.current)
    [
      Item.new("integrity", t(:integrity), true,
               check.present? && check.ok && check.created_at > 2.days.ago,
               check ? "#{check.created_at.to_date}: #{check.ok ? t(:no_problems) : check.problems.first(3).join('; ')}" : t(:never_run)),
      Item.new("backup", t(:backup), true,
               backup.present? && backup.ok && backup.created_at > 2.days.ago,
               backup ? "#{backup.created_at.to_date}: #{backup.message}" : t(:never_run)),
      *offsite_items,
      drs_item,
      Item.new("procedures", t(:procedures), true,
               revision.present? && @policy.complete?,
               revision ? t(:revision, number: revision.number, date: revision.adopted_at.to_date) : t(:not_adopted)),
      Item.new("signatures", t(:signatures), true,
               check.present? && check.ok, t(:signed_since, count: signatures_since.count, since: since_label)),
      Item.new("certificates", t(:certificates), true, true,
               expired.any? ? t(:expired_certificates, names: expired.map { "#{_1.user.display_name} #{_1.short_label}" }.join(", ")) : t(:none_expired)),
      Item.new("versions", t(:versions), true, true,
               versions_since.map { [ _1.version, t(:build, revision: _1.revision) ].compact.join(" ") }.join(", ").presence || t(:no_changes))
    ]
  end

  # Entries to compare with source documents: a random few since the last audit, signed ones first.
  def sample
    pool = LogbookEntry.where(created_at: (@since || Time.at(0))..).includes(:aircraft, :signature)
    signed = pool.joins(:signature).order(Arel.sql("RANDOM()")).limit(@policy.audit_sample_size).to_a
    (signed + pool.where.not(id: signed.map(&:id)).order(Arel.sql("RANDOM()")).limit(@policy.audit_sample_size - signed.size).to_a).first(@policy.audit_sample_size)
  end

  def users = User.order(:email_address).includes(:certificates, aircraft_roles: :aircraft)

  # Saves the audit from the auditor's answers: { key => { "passed" => "1", "note" => … } }.
  def record!(user:, answers:, notes:, sample_ids:)
    autos = auto_items
    manual = MANUAL.map do |key, title|
      a = answers.fetch(key, {})
      { "key" => key, "title" => title, "auto" => false, "passed" => a["passed"] == "1", "detail" => a["note"].to_s.strip.first(1000) }
    end
    results = autos.map { { "key" => _1.key, "title" => _1.title, "auto" => true, "passed" => _1.passed, "detail" => _1.detail } } + manual
    results << { "key" => "sample_entries", "title" => t(:entries_sampled), "auto" => true, "passed" => true,
                 "detail" => LogbookEntry.where(id: sample_ids).includes(:aircraft).map { "#{_1.aircraft.tail_number} #{_1.date}" }.join(", ") }
    AuditRun.create!(performed_by: user, performed_at: Time.current, passed: results.all? { _1["passed"] }, results: results, notes: notes.to_s.strip.first(5000))
  end

  # The latest automatic restore test (shown next to the manual restore item).
  def restore_test = OffsiteConnection.connected? ? OffsiteRun.latest_restore_test : nil

  private

  def drs_item
    due = Aircraft.ordered.select { DrsImport.renewal_due?(_1) || DrsImport.missing_models(_1).any? }
    Item.new("drs", t(:drs), true, due.empty?,
             due.any? ? t(:needs_drs, aircraft: due.map(&:tail_number).join(", ")) : t(:up_to_date))
  end

  def offsite_items
    return [] unless OffsiteConnection.connected?
    run = OffsiteRun.latest_backup
    [ Item.new("offsite", t(:offsite), true, run.present? && run.ok && run.recent?,
               run ? "#{run.created_at.to_date}: #{run.message}" : t(:never_run)) ]
  end

  def since_label = @since ? @since.to_date.to_s : t(:the_start)
  def t(key, **opts) = I18n.t(key, scope: "services.records_audit", **opts)
  def signatures_since = EntrySignature.where(signed_at: (@since || Time.at(0))..)
  def versions_since = AppRevision.where(first_seen_at: (@since || Time.at(0))..).order(:first_seen_at)
end
