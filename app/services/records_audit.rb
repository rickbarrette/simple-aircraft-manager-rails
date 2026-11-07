# The QC audit checklist (AC 120-78B 3.2.8.5): items the app checks itself,
# and items the auditor confirms (restore test, comparing a sample of entries
# with their source documents, reviewing users).
class RecordsAudit
  Item = Data.define(:key, :title, :auto, :passed, :detail)

  MANUAL = {
    "restore_test" => "Restored the latest off-site backup somewhere separate and opened it (records readable, counts plausible)",
    "sample" => "Compared the sampled entries below with their work orders, receipts or other source documents; they match",
    "users" => "Reviewed the users and roles below; accounts of people who no longer need access are disabled",
    "legacy" => "The paper (legacy) logbooks are kept, complete and accounted for"
  }.freeze

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
      Item.new("integrity", "Records integrity check passed in the last 2 days", true,
               check.present? && check.ok && check.created_at > 2.days.ago,
               check ? "#{check.created_at.to_date}: #{check.ok ? 'no problems' : check.problems.first(3).join('; ')}" : "Never run"),
      Item.new("backup", "A verified database backup was made in the last 2 days", true,
               backup.present? && backup.ok && backup.created_at > 2.days.ago,
               backup ? "#{backup.created_at.to_date}: #{backup.message}" : "Never run"),
      *offsite_items,
      Item.new("procedures", "The procedures document is adopted and its details filled in", true,
               revision.present? && @policy.complete?,
               revision ? "Revision #{revision.number}, adopted #{revision.adopted_at.to_date}" : "Not adopted yet"),
      Item.new("signatures", "Electronic signatures since the last audit are intact", true,
               check.present? && check.ok, "#{signatures_since.count} signed since #{since_label}"),
      Item.new("certificates", "No active user is relying on an expired certificate", true, true,
               expired.any? ? "Expired (can't sign until renewed): #{expired.map { "#{_1.user.display_name} #{_1.short_label}" }.join(', ')}" : "None expired"),
      Item.new("versions", "Software versions since the last audit", true, true,
               versions_since.map(&:revision).join(", ").presence || "No changes")
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
    results << { "key" => "sample_entries", "title" => "Entries sampled", "auto" => true, "passed" => true,
                 "detail" => LogbookEntry.where(id: sample_ids).includes(:aircraft).map { "#{_1.aircraft.tail_number} #{_1.date}" }.join(", ") }
    AuditRun.create!(performed_by: user, performed_at: Time.current, passed: results.all? { _1["passed"] }, results: results, notes: notes.to_s.strip.first(5000))
  end

  # The latest automatic restore test (shown next to the manual restore item).
  def restore_test = OffsiteConnection.connected? ? OffsiteRun.latest_restore_test : nil

  private

  def offsite_items
    return [] unless OffsiteConnection.connected?
    run = OffsiteRun.latest_backup
    [ Item.new("offsite", "The backup was copied off-site (Google Drive) in the last 2 days", true, run.present? && run.ok && run.recent?,
               run ? "#{run.created_at.to_date}: #{run.message}" : "Never run") ]
  end

  def since_label = @since ? @since.to_date.to_s : "the start"
  def signatures_since = EntrySignature.where(signed_at: (@since || Time.at(0))..)
  def versions_since = AppRevision.where(first_seen_at: (@since || Time.at(0))..).order(:first_seen_at)
end
