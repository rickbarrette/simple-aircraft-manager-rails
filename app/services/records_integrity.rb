# Verifies the records (AC 120-78B 3.2.2 / 3.2.4 / 3.2.8.5.3): each
# aircraft's history chain is unbroken, and every signature's seal and
# fingerprint still match. The result is kept as an IntegrityCheck.
class RecordsIntegrity
  def self.check! = new.check!

  def check!
    problems = []
    versions = 0
    RecordVersion.distinct.pluck(:aircraft_id).each do |aircraft_id|
      prev = nil
      RecordVersion.where(aircraft_id: aircraft_id).chronological.find_each do |v|
        versions += 1
        tail = Aircraft.find_by(id: aircraft_id)&.tail_number || "aircraft #{aircraft_id.inspect}"
        problems << "#{tail}: history entry #{v.id} doesn't follow the one before it (missing or reordered history)" if v.prev_hash != prev
        problems << "#{tail}: history entry #{v.id} was altered" if v.chain_hash != RecordVersion.digest(v.prev_hash, v.payload)
        prev = v.chain_hash
      end
    end
    signatures = 0
    EntrySignature.includes(logbook_entry: [ :aircraft, :parts ]).find_each do |sig|
      signatures += 1
      next if sig.imported? || sig.status != :altered
      entry = sig.logbook_entry
      problems << "#{entry.aircraft.tail_number}: the #{entry.date} logbook entry (signed by #{sig.signer_name}) " \
                  "#{sig.seal_valid? ? 'changed after it was signed' : 'has an altered signature'}"
    end
    AppRevision.touch_current!
    IntegrityCheck.create!(ok: problems.empty?, versions_checked: versions, signatures_checked: signatures, problems: problems.first(200))
  end
end
