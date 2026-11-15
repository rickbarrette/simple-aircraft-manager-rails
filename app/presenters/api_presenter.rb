# What the API and webhooks send for each kind of record (docs/api.md).
# Times are ISO 8601 UTC, hours decimals, codes rather than translated labels.
module ApiPresenter
  module_function

  def aircraft(a)
    aw = a.airworthiness
    { id: a.id, tail_number: a.tail_number, make: a.make, model: a.model, serial_number: a.serial_number,
      icao_type: a.icao_type, status: a.status,
      airworthiness: { status: aw.status, issues: aw.issues.map { { category: _1.category, severity: _1.severity, title: _1.title } } },
      time_basis: a.time_basis, hours: dec(a.current_hours), tach: dec(a.tach_time), hobbs: dec(a.hobbs_time),
      updated_at: time(a.updated_at) }
  end

  def component(c)
    { id: c.id, aircraft_id: c.aircraft_id, parent_id: c.parent_component_id, type: c.component_type&.name,
      manufacturer: c.manufacturer, model: c.model, serial_number: c.serial_number.presence,
      location: c.install_location.presence, status: c.status, date_in_service: c.date_in_service&.iso8601,
      hours_in_service: dec(c.hours_in_service), hours_since_overhaul: dec(c.hours_since_overhaul),
      overhaul_date: c.overhaul_date&.iso8601, overhaul_kind: c.overhaul_kind.presence,
      tbo: { hours: c.tbo_hours, days: c.tbo_days, months: c.tbo_months, on_condition: c.on_condition, critical: c.tbo_critical }.compact,
      replacement: { hours: c.replacement_hours, days: c.replacement_days, months: c.replacement_months, critical: c.replacement_critical }.compact,
      expires_on: c.expires_on&.iso8601, updated_at: time(c.updated_at) }
  end

  def due_item(i)
    { key: i.key, title: i.title, kind: i.kind, due_date: i.date.iso8601, projected: i.projected,
      due_hours: dec(i.due_hours), overdue: i.overdue? }
  end

  def squawk(s)
    { id: s.id, aircraft_id: s.aircraft_id, component_id: s.component_id, issue_reported: s.issue_reported,
      priority: s.priority, grounding: s.grounding?, deferred: s.deferred?, resolved: !!s.resolved,
      resolved_at: time(s.resolved_at), notes: s.notes.presence, logbook_entry_id: s.logbook_entry_id,
      reported_by: s.reported_by&.display_name, external_ref: s.external_ref,
      attachments: s.attachments.map { _1.filename.to_s },
      created_at: time(s.created_at), updated_at: time(s.updated_at) }
  end

  def logbook_entry(e)
    sig = e.signature
    { id: e.id, aircraft_id: e.aircraft_id, component_id: e.component_id, log: e.log_type, entry_type: e.entry_type,
      date: e.date.iso8601, text: e.text, aircraft_hours: dec(e.aircraft_hours_at_entry),
      inspection_result: e.inspection_result.presence, verified: e.verified, superseded: e.superseded_at.present?,
      signed: sig.present?, signature: sig && signature(sig), draft_batch_id: e.draft_batch_id, external_ref: e.external_ref,
      signoff: sig ? nil : { person: e.signoff_person.presence, certificate_type: e.signoff_certificate_type.presence,
                             certificate_number: e.signoff_certificate_number.presence }.compact.presence,
      created_at: time(e.created_at), updated_at: time(e.updated_at) }
  end

  def draft_batch(b, invitations: {})
    urls = Rails.application.routes.url_helpers
    { id: b.id, aircraft_id: b.aircraft_id, status: b.status, external_ref: b.external_ref, signer_email: b.signer_email,
      held: { resolves_squawks: b.held_squawks.map { _1["id"] }, completes_inspections: b.held_inspections.map { _1["id"] } },
      entries: b.entries.sort_by(&:log_type).map do |e|
        logbook_entry(e).merge(sign_url: "#{Sso.app_url}#{urls.new_aircraft_logbook_entry_signature_path(b.aircraft_id, e)}",
                               invitation_url: invitations[e.id] && "#{Sso.app_url}#{urls.invited_signing_path(invitations[e.id])}")
      end,
      completed_at: time(b.completed_at), created_at: time(b.created_at) }
  end

  def signature(sig)
    { signer_name: sig.signer_name, certificate_kind: sig.certificate_kind, certificate_number: sig.certificate_number,
      signed_at: time(sig.signed_at) }
  end

  def inspection(row)
    { inspection_type_id: row.type.id, name: row.type.name, status: row.status, next_due_date: row.next_due_date&.iso8601,
      next_due_hours: dec(row.next_due_hours), last_done: row.latest&.date&.iso8601 }
  end

  def ad(row)
    { airworthiness_directive_id: row.ad.id, name: row.ad.name, description: row.ad.short_description.presence,
      status: row.status, next_due_date: row.next_due_date&.iso8601, next_due_hours: dec(row.next_due_hours),
      last_complied: row.latest&.date_complied&.iso8601 }
  end

  def dec(value) = value&.to_d&.round(1)&.to_f
  def time(value) = value&.utc&.iso8601
end
